import base64, json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
# Server-side timestamps per document: "older" is far in the past, "newer" far in the future.
STATE = {"docC": 1000, "docB": 4102444800}
OK_AUTH = "Basic " + base64.b64encode(b"alice:secret").decode()
class H(BaseHTTPRequestHandler):
    def _send(self, code, body):
        self.send_response(code); self.send_header("Content-Type", "application/json"); self.end_headers()
        self.wfile.write(json.dumps(body).encode())
    def _auth(self):
        print("REQ", self.command, self.path, "accept=" + str(self.headers.get("Accept")), flush=True)
        if self.headers.get("Authorization") != OK_AUTH:
            self._send(401, {"message": "Unauthorized"}); return False
        return True
    def do_GET(self):
        if not self._auth(): return
        doc = self.path.rsplit("/", 1)[-1]
        self._send(200, {"document": doc, "timestamp": STATE[doc]} if doc in STATE else {})
    def do_PUT(self):
        if not self._auth(): return
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        print("PUT_BODY", json.dumps(body, sort_keys=True), flush=True)
        self._send(200, {"document": body["document"], "timestamp": 1})
    def log_message(self, *a): pass
HTTPServer(("127.0.0.1", 8765), H).serve_forever()
