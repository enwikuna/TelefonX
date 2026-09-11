#!/usr/bin/env python3
"""An in-memory loopback registrar verifies actual SIP Digest authentication."""
import hashlib
import re
import socket
import threading
import time
from loopback import Peer

def md5(value):
    return hashlib.md5(value.encode()).hexdigest()

class Registrar:
    def __init__(self):
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.socket.bind(("127.0.0.1", 0)); self.port = self.socket.getsockname()[1]
        self.socket.settimeout(0.2)
        self.running = True; self.registered = 0; self.unregistered = 0; self.rejected = 0; self.errors = []
        self.thread = threading.Thread(target=self.run, daemon=True); self.thread.start()

    def run(self):
        while self.running:
            try:
                data, peer = self.socket.recvfrom(65535)
            except socket.timeout:
                continue
            except OSError:
                break
            try:
                lines = data.decode().split("\r\n")
                assert lines[0].startswith("REGISTER "), lines[0]
                headers = {}
                for line in lines[1:]:
                    if ":" in line:
                        key, value = line.split(":", 1)
                        headers.setdefault(key.lower(), []).append(value.strip())
                authorization = headers.get("authorization", [""])[0]
                auth = {key: (quoted or bare) for key, quoted, bare in re.findall(r'(\w+)=(?:"([^"]*)"|([^,\s]+))', authorization)}
                status, extra = "401 Unauthorized", ['WWW-Authenticate: Digest realm="telefonx-test", nonce="local-test-nonce", algorithm=MD5, qop="auth"']
                if authorization:
                    ha1 = md5("peer:telefonx-test:test-only")
                    ha2 = md5("REGISTER:" + auth.get("uri", ""))
                    expected = md5(":".join([ha1, "local-test-nonce", auth.get("nc", ""), auth.get("cnonce", ""), "auth", ha2]))
                    if auth.get("response") == expected and auth.get("username") == "peer":
                        expiry = headers.get("expires", ["300"])[0]
                        status = "200 OK"
                        extra = ["Expires: " + expiry] + ["Contact: " + contact for contact in headers.get("contact", [])]
                        if expiry == "0": self.unregistered += 1
                        else: self.registered += 1
                    else:
                        status, extra = "403 Forbidden", []
                        self.rejected += 1
                response = ["SIP/2.0 " + status]
                response += ["Via: " + via for via in headers["via"]]
                response += ["From: " + headers["from"][0], "To: " + headers["to"][0] + ";tag=local-test",
                             "Call-ID: " + headers["call-id"][0], "CSeq: " + headers["cseq"][0]]
                response += extra + ["Content-Length: 0", "", ""]
                self.socket.sendto("\r\n".join(response).encode(), peer)
            except Exception as error:
                self.errors.append(str(error))

    def close(self):
        self.running = False; self.thread.join(timeout=1); self.socket.close()

def wait_for(predicate, seconds=6):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate(): return
        time.sleep(0.05)
    assert predicate(), "Registrar expectation timed out"

if __name__ == "__main__":
    server, peer = Registrar(), None
    try:
        peer = Peer("opus")
        peer.ok(f"REGISTER 127.0.0.1:{server.port} test-only")
        peer.wait(lambda line: line.startswith("EVENT 1 1 200 "))
        assert server.registered == 1
        peer.ok("REFRESH")
        wait_for(lambda: server.registered >= 2)
        peer.ok("NETWORK")
        wait_for(lambda: server.registered >= 3)
        peer.ok("UNREGISTER")
        wait_for(lambda: server.unregistered >= 1)
        peer.ok(f"REGISTER 127.0.0.1:{server.port} deliberately-wrong")
        peer.wait(lambda line: line.startswith("EVENT 1 0 403 "))
        assert server.rejected >= 1 and not server.errors, server.errors
        peer.stop()
        print("PASS SIP Digest: challenge/response verified, call-time refresh, IP-change re-registration, expires=0 unregister, wrong-password 403")
    finally:
        if peer is not None and peer.process.poll() is None: peer.stop()
        server.close()
