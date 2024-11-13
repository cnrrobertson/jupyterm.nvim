import pynvim
from jupyter_client import KernelManager
import base64
import tempfile
from PIL import Image
import threading

@pynvim.plugin
class Jupyterm(object):
    def __init__(self, nvim):
        self.nvim = nvim
        self.kernels = {}
        self.lock = threading.Lock()

    def _check_kernel(self, kernel):
        with self.lock:
            return kernel in self.kernels

    @pynvim.function("JupyStart", sync=True)
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

    @pynvim.command("JupyShutdown", nargs="1", sync=True)
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

    def start(self):
        self.km = KernelManager()
        self.km.start_kernel()
        self.kc = self.km.client()
        self.kc.start_channels()
        self.kc.wait_for_ready()

    def execute(self, args):
        code = "".join(args)
        threading.Thread(target=self.execute_on_thread, args=(code,)).start()

    def execute_on_thread(self, code):
        with self.lock:
            self.inputs.append(code)
            self.outputs.append("Computing...")
            self.kc.execute(code)

            input_received = False
            while True:
                try:
                    msg = self.kc.get_iopub_msg(timeout=10)
                    if msg:
                        # input_received = self.handle_message(msg)
                        msg_type = msg["msg_type"]
                        content = msg["content"]

                        if msg_type == "execute_input":
                            input_received = True
                        elif msg_type == "status":
                            pass
                        elif msg_type == "execute_reply":
                            pass
                        elif msg_type == "execute_result":
                            if "text/plain" in content["data"]:
                                self.outputs[-1] = content["data"]["text/plain"]
                                break
                        elif msg_type == "error":
                            self.outputs[-1] = f"{content['ename']}: {content['evalue']}"
                            break
                        elif msg_type == "stream":
                            self.outputs[-1] = content["text"]
                            break
                        elif msg_type == "display_data":
                            self.handle_display_data(content)
                            break
                        elif msg_type == "update_display_data":
                            pass
                        elif msg_type == "clear_output":
                            pass
                        if msg["msg_type"] == "status" and msg["content"]["execution_state"] == "idle" and input_received:
                            self.outputs[-1] = ""
                            break
                except Exception as e:
                    self.nvim.async_call(self.nvim.out_write, f"Error: {str(e)}\n")
                    break

    def handle_display_data(self, content):
        img_data = content["data"].get("image/png")
        if img_data:
            with tempfile.NamedTemporaryFile(delete=False, suffix=".png") as f:
                f.write(base64.b64decode(img_data))
                tmp_file_path = f.name
            self.outputs[-1] = f"[Image]:\n{tmp_file_path}"

            img_file = Image.open(tmp_file_path)
            img_file.show()

    def get_input_output(self):
        with self.lock:
            return self.inputs, self.outputs

    def shutdown(self):
        self.kc.stop_channels()
        self.km.shutdown_kernel()

