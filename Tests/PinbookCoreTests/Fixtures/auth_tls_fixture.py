"""Synthetic loopback-only TLS fixture. Never accepts production credentials."""
import http.server
import base64
import hashlib
import json
import pathlib
import socket
import ssl
import sys
import time

root = pathlib.Path(sys.argv[1])
mode = sys.argv[2]
token = lambda char: char * 42 + "A"


def key_thumbprint(jwk):
    canonical = json.dumps(jwk, sort_keys=True, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(hashlib.sha256(canonical).digest()).decode().rstrip("=")


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
            output.write(json.dumps({"method": self.command, "path": self.path,
                                     "authorization": self.headers.get("Authorization")}) + "\n")
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
        if self.path.endswith(("/refresh", "/exchange", "/invited-exchange")):
            fields = {"accountId": "public-account", "sessionId": "public-session",
                      "accessToken": token("C"), "refreshToken": token("D"),
                      "accessExpiresAt": 10000, "sessionExpiresAt": 30000}
        if self.path == "/api/v1/invitations/preview":
            fields = {"inviteId": "public-invite", "teamId": "public-team",
                      "role": "MEMBER", "expiresAt": 20000}
        if self.path in ("/api/v1/teams/current", "/api/v1/teams/accept"):
            fields = {"teamId": "public-team", "accountId": "public-account",
                      "enrollmentId": "public-enrollment", "role": "MEMBER",
                      "membershipRevision": 1}
        if self.path == "/api/v1/teams/acceptance":
            # Response-shape fixture, not backend eligibility/locking logic.
            fields = {"membership": None if mode == "acceptance-pending" else {
                "teamId": "public-team", "accountId": "public-account",
                "enrollmentId": "public-enrollment", "role": "MEMBER",
                "membershipRevision": 1}}
        if self.path == "/api/v1/teams/invites/list":
            fields = {"invitations": [{"inviteId": f"public-invite-{i}", "role": "MEMBER",
                                       "state": "PENDING", "expiresAt": 20000} for i in range(100)]}
        if self.path == "/api/v1/devices/lookup":
            fields = {"registration": None}
            saved = root / "device-registration.json"
            if saved.exists():
                registration = json.loads(saved.read_text())
                request = json.loads(body)
                if registration["deviceId"] == request["deviceId"] and registration["keyThumbprint"] == key_thumbprint(request["publicKey"]):
                    fields["registration"] = registration
        if self.path == "/api/v1/devices/challenge":
            request = json.loads(body)
            thumb = key_thumbprint(request["publicKey"])
            fields = {"audience": "https://" + self.headers["Host"], "authorityEpoch": "public-epoch",
                      "accountId": "public-account", "sessionId": "public-session",
                      "deviceId": request["deviceId"], "keyThumbprint": thumb,
                      "challengeId": token("A"), "nonce": token("B"), "expiresAt": 9000}
            (root / "device-public.json").write_text(json.dumps(fields))
        if self.path == "/api/v1/devices/complete":
            # Transport fixture only. The Swift test independently verifies the
            # exact transmitted signature; this is not a real enrollment service.
            challenge = json.loads((root / "device-public.json").read_text())
            fields = {key: challenge[key] for key in ("accountId", "deviceId", "keyThumbprint", "authorityEpoch")}
            fields["enrollmentId"] = "public-enrollment"
            (root / "device-registration.json").write_text(json.dumps(fields))
        if mode in ("503", "408"):
            status = int(mode)
            fields = {"error": "uncertain" if mode == "503" else "request_timeout"}
        if mode == "join-uncertain" and self.path == "/api/v1/teams/accept":
            status = 503
            fields = {"error": "uncertain"}
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
