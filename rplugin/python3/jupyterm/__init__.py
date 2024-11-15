import pynvim
from jupyter_client import KernelManager
# from jupyter_client.kernelspec import KernelSpecManager
import base64
import tempfile
from PIL import Image
import threading
import queue
import re

@pynvim.plugin
class Jupyterm(object):
    def __init__(self, nvim):
        self.nvim = nvim
        self.kernels = {}
        self.lock = threading.Lock()
        # ksm = KernelSpecManager()
        # kernels = ksm.find_kernel_specs()
        # self.nvim.out_write("Available kernels:\n")
        # for name, path in kernels.items():
        #     self.nvim.out_write(f"{name}: {path}\n")

    def _check_kernel(self, kernel):
        with self.lock:
            return kernel in self.kernels

    @pynvim.function("JupyStart", sync=False)
    def start(self, args):
        kernel_name = args[0]
        if not self._check_kernel(kernel_name):
            kernel = Kernel(self.nvim)
            kernel.start()
            with self.lock:
                self.kernels[kernel_name] = kernel
            self.nvim.out_write(f"Kernel '{kernel_name}' started.\n")

    @pynvim.function("JupyEval", sync=False)
    def executef(self, args):
        kernel_name = args[0]
        if self._check_kernel(kernel_name):
            self.kernels[kernel_name].execute(args[1:])
        else:
            self.nvim.out_write(f"Kernel '{kernel_name}' is not running.\n")

    @pynvim.command("JupyExec", nargs="*", sync=False)
    def executec(self, args):
        self.executef(args)

    @pynvim.function("JupyOutput", sync=True)
    def get_input_output(self, args):
        kernel_name = args[0]
        if self._check_kernel(kernel_name):
            kernel = self.kernels[kernel_name]
            return kernel.get_input_output()
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

class Kernel(object):
    def __init__(self, nvim):
        self.nvim = nvim
        self.inputs = []
        self.outputs = []
        self.lock = threading.Lock()
        self.queue = queue.Queue()
        self.wait_str = "Computing..."
        self.queue_str = "Queued"

    def start(self):
        self.km = KernelManager()
        self.km.start_kernel()
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
                self.outputs[oloc] = self.wait_str
            iopub = threading.Thread(target=self.listen_to_iopub, args=(oloc,))
            iopub.start()
            self.kc.execute(code)
            iopub.join()

    def execute(self, args):
        code = "".join(args)
        with self.lock:
            self.inputs.append(code)
            self.outputs.append(self.queue_str)
            oloc = len(self.outputs) - 1
            self.queue.put((code, oloc))


    def listen_to_iopub(self, oloc):
        seen_input = False
        seen_output = False
        idle = False
        while not (seen_input and seen_output and idle):
            try:
                msg = self.kc.get_iopub_msg()
                if msg:
                    seen_input, seen_output, idle = self.handle_iopub_message(msg, seen_input, seen_output, oloc)
            except Exception as e:
                self.nvim.async_call(self.nvim.out_write, f"IOPub error: {str(e)}\n")
                pass

    def handle_iopub_message(self, msg, seen_input, seen_output, oloc):
        with self.lock:
            msg_type = msg["msg_type"]
            content = msg["content"]

            if msg_type == "execute_input":
                seen_input = True
            elif msg_type == "status":
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
                self.update_output(oloc, f"{content['ename']}: {content['evalue']}")
                seen_output = True
            elif msg_type == "stream":
                if content["name"] == "stderr":
                    processed_str = "".join(content['text'].splitlines())
                    self.update_output(oloc, "stderr:"+processed_str+"\n")
                else:
                    self.update_output(oloc, content['text'])
                seen_output = True
            elif msg_type == "display_data":
                self.handle_display_data(content, oloc)
                seen_output = True
            elif msg_type == "update_display_data":
                pass
            elif msg_type == "clear_output":
                pass
        return seen_input, seen_output, False

    def update_output(self, oloc, new_addition, final=False):
        # Remove wait_str
        output = self.outputs[oloc].replace(self.wait_str, "")

        # Check stderr
        if "stderr:" in new_addition:
            if new_addition.strip() == "stderr:":
                return
            if "stderr:" in output:
                self.outputs[oloc] = re.sub(r'^stderr:.*$', new_addition, output.replace("\n\n","\n"), flags=re.MULTILINE)
                return

        # Deal with ANSI control characters
        processed_addition = re.sub(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])', '', new_addition)

        # Finish
        if final:
            self.outputs[oloc] = output + processed_addition
        else:
            self.outputs[oloc] = output + processed_addition + self.wait_str

    def handle_display_data(self, content, oloc):
        img_data = content["data"].get("image/png")
        if img_data:
            with tempfile.NamedTemporaryFile(delete=False, suffix=".png") as f:
                f.write(base64.b64decode(img_data))
                tmp_file_path = f.name
            self.update_output(oloc, f"[Image]:\n{tmp_file_path}")

            img_file = Image.open(tmp_file_path)
            img_file.show()

    def interrupt(self):
        self.km.interrupt_kernel()

    def get_input_output(self):
        with self.lock:
            return self.inputs, self.outputs

    def shutdown(self):
        self.kc.stop_channels()
        self.km.shutdown_kernel()
