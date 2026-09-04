"""Synthetic loopback-only TLS fixture. Never accepts production credentials."""
import http.server
import json
import pathlib
import socket
import ssl
import sys
import time

root = pathlib.Path(sys.argv[1])
mode = sys.argv[2]
token = lambda char: char * 42 + "A"


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def do_GET(self):
        self.respond()

    def do_POST(self):
        self.respond()

    def respond(self):
        self.connection.settimeout(2)
        size = int(self.headers.get("Content-Length", "0"))
        # Record the attempt before reading, so retries with exhausted streams
        # cannot hide behind a body timeout. All values are public test fixtures.
        with (root / "attempts.jsonl").open("a") as output:
            output.write(json.dumps({"method": self.command, "path": self.path}) + "\n")
        if not 0 <= size <= 20_000:
            self.close_connection = True
            return
        try:
            body = self.rfile.read(size)
        except (TimeoutError, OSError):
            return
        with (root / "bodies.jsonl").open("a") as output:
            output.write(json.dumps({"body": body.decode(), "size": size}) + "\n")
        if mode == "drop":
            self.connection.shutdown(socket.SHUT_RDWR)
            self.connection.close()
            self.close_connection = True
            return
        status = 200
        fields = {"challengeId": token("A"), "nonce": token("B"), "expiresAt": 121000}
        if self.path.endswith("/refresh"):
            fields = {"accountId": "public-account", "sessionId": "public-session",
                      "accessToken": token("C"), "refreshToken": token("D"),
                      "accessExpiresAt": 10000, "sessionExpiresAt": 30000}
        if mode in ("503", "408"):
            status = int(mode)
            fields = {"error": "uncertain" if mode == "503" else "request_timeout"}
        if mode == "redirect":
            status = 307
        payload = json.dumps(fields).encode()
        if mode in ("oversize", "chunked"):
            payload = b" " * 32769
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Connection", "close")
        if mode in ("503", "408"):
            self.send_header("Retry-After", "0")
        if mode == "redirect":
            self.send_header("Location", "/must-not-follow")
        if mode == "chunked":
            self.send_header("Transfer-Encoding", "chunked")
        else:
            self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        try:
            if mode == "stall":
                time.sleep(20)
            if mode == "chunked":
                for offset in range(0, len(payload), 1024):
                    chunk = payload[offset:offset + 1024]
                    self.wfile.write(f"{len(chunk):x}\r\n".encode() + chunk + b"\r\n")
                self.wfile.write(b"0\r\n\r\n")
            else:
                self.wfile.write(payload)
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
            pass
        self.close_connection = True


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.minimum_version = ssl.TLSVersion.TLSv1_2
context.load_cert_chain(root / "certificate.pem", root / "private.pem")
server.socket = context.wrap_socket(server.socket, server_side=True)
(root / "port").write_text(str(server.server_port))
server.serve_forever()
