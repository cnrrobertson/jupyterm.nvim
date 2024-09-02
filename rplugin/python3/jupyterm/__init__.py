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
        self.inputs = []
        self.outputs = []
        self.lock = threading.Lock()

    @pynvim.command("JupyStart", nargs="*", sync=False)
    def start(self, args):
        self.km = KernelManager()
        self.km.start_kernel()
        self.kc = self.km.client()
        self.kc.start_channels()
        self.kc.wait_for_ready()

    @pynvim.function("JupyEval", sync=False)
    def evaluate(self, args):
        self.execute(args)

    @pynvim.function("JupyEvalList", sync=False)
    def evaluatelist(self, args):
        self.execute(*args)

    @pynvim.command("JupyExec", nargs="*", sync=False)
    def execute(self, args):
        code = "".join(args)
        threading.Thread(target=self.execute_on_thread, args=[code]).start()

    def execute_on_thread(self, code):
        with self.lock:
            self.inputs.append(code)
            self.outputs.append("Computing...")
            self.kc.execute(code)

            input = False
            while True:
                msg = self.kc.get_iopub_msg(timeout=10)

                msg_type = msg["msg_type"]
                content = msg["content"]
                if msg_type == "execute_input":
                    input = True
                elif msg_type == "status":
                    state = content["execution_state"]
                    if (state == "idle") & input:
                        self.outputs[-1] = ""
                        break
                elif msg_type == "execute_reply":
                    self.outputs[-1] = ""
                    pass
                elif msg_type == "execute_result":
                    if "text/plain" in content["data"]:
                        self.outputs[-1] = content["data"]["text/plain"]
                elif msg_type == "error":
                    self.outputs[-1] = f"{content['ename']}: {content['evalue']}"
                    break
                elif msg_type == "stream":
                    self.outputs[-1] = content["text"]
                    break
                elif msg_type == "display_data":
                    # Save image
                    img = content["data"]["image/png"]
                    with tempfile.NamedTemporaryFile(delete=False, suffix=".png") as f:
                        f.write(base64.b64decode(img))
                        tmp_file_path = f.name
                    self.outputs[-1] = f"[Image]:\n{tmp_file_path}"

                    # Show image
                    img_file = Image.open(tmp_file_path)
                    img_file.show()
                elif msg_type == "update_display_data":
                    pass
                elif msg_type == "clear_output":
                    if content["wait"]:
                        pass
                    else:
                        pass

    @pynvim.function("JupyOutput", sync=True)
    def get_input_output(self, args):
        return self.inputs, self.outputs

    @pynvim.command("JupyShutdown", sync=False)
    def shutdown(self):
        self.kc.stop_channels()
        self.km.shutdown_kernel()
