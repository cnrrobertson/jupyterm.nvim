import pynvim
from jupyter_client import KernelManager
import base64
import tempfile
try:
    from PIL import Image
    pillow_installed = True
except ImportError:
    pillow_installed = False
import threading
import queue
import re
import time
import datetime

@pynvim.plugin
class Jupyterm(object):
    def __init__(self, nvim):
        self.nvim = nvim
        self.kernels = {}
        self.lock = threading.Lock()

    def _check_kernel(self, kernel):
        with self.lock:
            return kernel in self.kernels

    @pynvim.function("JupyStart", sync=False)
    def start(self, args):
        kernel_id = args[0]
        cwd = args[1]
        kernel_name = args[2]
        wait_str = args[3]
        queue_str = args[4]
        if not self._check_kernel(kernel_id):
            kernel = Kernel(self.nvim, cwd, kernel_name, wait_str, queue_str)
            kernel.start()
            with self.lock:
                self.kernels[kernel_id] = kernel
            self.nvim.out_write(f"Kernel '{kernel_id}' started.\n")

    @pynvim.function("JupyEval", sync=False)
    def executef(self, args):
        kernel_name = args[0]
        if self._check_kernel(kernel_name):
            self.kernels[kernel_name].execute(args[1:])
        else:
            self.nvim.out_write(f"Kernel '{kernel_name}' is not running.\n")

    @pynvim.function("JupyOutput", sync=True)
    def get_input_output(self, args):
        kernel_name = args[0]
        if self._check_kernel(kernel_name):
            kernel = self.kernels[kernel_name]
            return kernel.get_input_output()
        else:
            self.nvim.out_write(f"Kernel '{kernel_name}' is not running.\n")
            return [], []

    @pynvim.function("JupyOutputLen", sync=True)
    def get_output_len(self, args):
        kernel_name = args[0]
        if self._check_kernel(kernel_name):
            kernel = self.kernels[kernel_name]
            return kernel.get_output_len()
        else:
            self.nvim.out_write(f"Kernel '{kernel_name}' is not running.\n")
            return [], []

    @pynvim.function("JupyInterrupt", sync=False)
    def interrupt(self, args):
        kernel_name = args[0]
        if self._check_kernel(kernel_name):
            kernel = self.kernels[kernel_name]
            self.nvim.out_write(f"Interrupting kernel '{kernel_name}'.\n")
            kernel.interrupt()
            self.nvim.out_write(f"Kernel '{kernel_name}' interrupted.\n")
        else:
            self.nvim.out_write(f"Kernel '{kernel_name}' is not running.\n")
            return [], []

    @pynvim.function("JupyShutdown", sync=False)
    def shutdown(self, args):
        kernel_name = args[0]
        if self._check_kernel(kernel_name):
            kernel = self.kernels[kernel_name]
            kernel.shutdown()
            with self.lock:
                self.kernels.pop(kernel_name)
            self.nvim.out_write(f"Kernel '{kernel_name}' shut down.\n")
        else:
            self.nvim.out_write(f"Kernel '{kernel_name}' is not running.\n")

    @pynvim.function("JupyRestart", sync=False)
    def restart(self, args):
        kernel_name = args[0]
        if self._check_kernel(kernel_name):
            kernel = self.kernels[kernel_name]
            kernel.restart()
            self.nvim.out_write(f"Kernel '{kernel_name}' restarted.\n")
        else:
            self.nvim.out_write(f"Kernel '{kernel_name}' is not running.\n")

    @pynvim.function("JupyStatus", sync=True)
    def status(self, args):
        kernel_name = args[0]
        if self._check_kernel(kernel_name):
            kernel = self.kernels[kernel_name]
            status = kernel.get_status()
            self.nvim.out_write(f"Kernel '{kernel_name}' status: {status}\n")
        else:
            self.nvim.out_write(f"Kernel '{kernel_name}' is not running.\n")

class Kernel(object):
    def __init__(self, nvim, cwd=".", kernel_name="python3", wait_str = "Computing...", queue_str = "Queued"):
        self.nvim = nvim
        self.inputs = []
        self.outputs = []
        self.start_times = []
        self.durations = []
        self.duration_timers = {}
        self.cwd = cwd
        self.kernel_name = kernel_name
        self.lock = threading.Lock()
        self.queue = queue.Queue()
        self.wait_str = wait_str
        self.queue_str = queue_str
        self.kernel_status = "Initialized"

    def start(self):
        self.km = KernelManager(kernel_name=self.kernel_name)
        self.km.start_kernel(cwd=self.cwd)
        self.kc = self.km.client()
        self.kc.start_channels()
        self.kc.wait_for_ready()

        # Start thread to monitor executions
        self.thread = threading.Thread(target=self.execution_monitor, daemon=True)
        self.thread.start()

    def execution_monitor(self):
        while True:
            code,oloc = self.queue.get()
            with self.lock:
                self.outputs[oloc] = self.wait_str + " (-)"
            if len(code) > 0:
                if (code.strip()[0] == "?") | (code.strip()[-1] == "?"):
                    iopub = threading.Thread(target=self.handle_helpdoc, args=(code, oloc))
                    iopub.start()
                    iopub.join()
                else:
                    iopub = threading.Thread(target=self.listen_to_iopub, args=(oloc,))
                    iopub.start()
                    with self.lock:
                        self.start_times[oloc] = time.time()
                    self.kc.execute(code)
                    iopub.join()
            else:
                with self.lock:
                    self.outputs[oloc] = ""

    def execute(self, args):
        code = "".join(args)
        with self.lock:
            self.inputs.append(code)
            self.outputs.append(self.queue_str)
            self.start_times.append(time.time())
            self.durations.append(0)
            oloc = len(self.outputs) - 1
            self.queue.put((code, oloc))

    def handle_helpdoc(self, code, oloc):
        info = self.kc.inspect(code, detail_level=0, reply=True)
        with self.lock:
            if "text/plain" in info["content"]["data"].keys():
                processed_info = self.handle_ansi_cc(info["content"]["data"]["text/plain"])
                self.outputs[oloc] = f"{processed_info}"
            else:
                self.outputs[oloc] = "No info from kernel."

    def timer_update(self, oloc):
        while self.duration_timers.get(oloc, False):
            with self.lock:
                self.durations[oloc] = time.time() - self.start_times[oloc]
                self.update_output(oloc, "")
            time.sleep(0.5)

    def listen_to_iopub(self, oloc):
        seen_input = False
        seen_output = False
        idle = False
        self.duration_timers[oloc] = True
        timer_thread = threading.Thread(target=self.timer_update, args=(oloc,))
        timer_thread.start()
        while not (seen_input and seen_output and idle):
            try:
                msg = self.kc.get_iopub_msg()
                if msg:
                    seen_input, seen_output, idle = self.handle_iopub_message(msg, seen_input, seen_output, oloc)
            except Exception as e:
                self.nvim.async_call(self.nvim.out_write, f"IOPub error: {str(e)}\n")
                pass
        self.duration_timers[oloc] = False
        timer_thread.join()

    def handle_iopub_message(self, msg, seen_input, seen_output, oloc):
        with self.lock:
            msg_type = msg["msg_type"]
            content = msg["content"]

            if msg_type == "execute_input":
                seen_input = True
            elif msg_type == "status":
                self.kernel_status = content["execution_state"]
                if "idle" in content['execution_state'] and seen_input:
                    self.update_output(oloc, "", True)
                    return seen_input, True, True
            elif msg_type == "execute_reply":
                pass
            elif msg_type == "execute_result":
                if "text/plain" in content["data"]:
                    self.update_output(oloc, content["data"]["text/plain"])
                    seen_output = True
            elif msg_type == "error":
                self.update_output(oloc, f"{content['ename']}: {content['evalue']}\n")
                for trace in content['traceback']:
                    processed_trace = self.handle_ansi_cc(trace).strip("\n")
                    self.update_output(oloc, f"{processed_trace}\n")
                seen_output = True
            elif msg_type == "stream":
                if content["name"] == "stderr":
                    self.update_output(oloc, "stderr:"+content['text']+"\n")
                else:
                    self.update_output(oloc, content['text']+"\n")
                seen_output = True
            elif msg_type == "display_data":
                self.handle_image_display(content, oloc)
                if "text/plain" in content["data"].keys():
                    self.update_output(oloc, content["data"]["text/plain"]+"\n")
                seen_output = True
            elif msg_type == "update_display_data":
                pass
            elif msg_type == "clear_output":
                pass
        return seen_input, seen_output, False

    def update_output(self, oloc, new_addition, final=False):
        output = self.outputs[oloc]

        # Check stderr
        if "stderr:" in new_addition:
            if new_addition.strip() == "stderr:":
                return
            if "stderr:" in output:
                self.outputs[oloc] = re.sub(r'^stderr:.*$', new_addition, output.replace("\n\n","\n"), flags=re.MULTILINE)
                return

        # Remove wait_str
        output = re.sub(rf"{re.escape(self.wait_str)}(?:\s\(.+\))?", "", output)

        # Deal with ANSI control characters
        processed_addition = self.handle_ansi_cc(new_addition)

        # Finish
        duration = datetime.timedelta(seconds=self.durations[oloc])
        if duration < datetime.timedelta(seconds=1):
            duration = ""
        elif final:
            duration = f"Duration: {duration}"
        else:
            duration = f" (Elapsed: {duration})"
        if final:
            self.outputs[oloc] = output + processed_addition + duration
        else:
            self.outputs[oloc] = output + processed_addition + self.wait_str + duration

    def handle_image_display(self, content, oloc):
        img_data = content["data"].get("image/png")
        if img_data:
            with tempfile.NamedTemporaryFile(delete=False, suffix=".png") as f:
                f.write(base64.b64decode(img_data))
                tmp_file_path = f.name
            self.update_output(oloc, f"[Image]:\n{tmp_file_path}\n")

            if pillow_installed:
                img_file = Image.open(tmp_file_path)
                img_file.show()
            else:
                self.nvim.async_call(self.nvim.out_write, "Image not displayed: `pillow` not installed in python env.")

    def handle_ansi_cc(self, entry):
        return re.sub(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])', '', entry)

    def interrupt(self):
        self.km.interrupt_kernel()

    def get_input_output(self):
        with self.lock:
            return self.inputs, self.outputs, self.durations

    def get_output_len(self):
        with self.lock:
            return len(self.outputs)

    def get_status(self):
        with self.lock:
            return self.kernel_status

    def shutdown(self):
        self.kc.stop_channels()
        self.km.shutdown_kernel()

    def restart(self):
        self.inputs = []
        self.outputs = []
        self.km.restart_kernel()
