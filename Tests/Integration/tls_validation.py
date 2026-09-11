#!/usr/bin/env python3
"""Verify the native engine rejects an untrusted TLS server without trusting a test CA."""
import pathlib
import socket
import ssl
import subprocess
import tempfile
import threading
from loopback import Peer

if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="telefonx-tls-") as raw:
        directory = pathlib.Path(raw)
        openssl = "/opt/homebrew/opt/openssl@3/bin/openssl"
        if not pathlib.Path(openssl).exists(): openssl = "/usr/bin/openssl"
        subprocess.run([openssl, "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                        "-subj", "/CN=telefonx-untrusted.invalid", "-keyout", str(directory / "key.pem"),
                        "-out", str(directory / "cert.pem")], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(directory / "cert.pem", directory / "key.pem")
        listener = socket.socket(); listener.bind(("127.0.0.1", 0)); listener.listen(3); listener.settimeout(12)
        port = listener.getsockname()[1]
        outcomes = []
        def serve():
            try:
                connection, _ = listener.accept()
                connection.settimeout(5)
                try:
                    with context.wrap_socket(connection, server_side=True) as secure:
                        outcomes.append(("accepted", secure.recv(4096)))
                except ssl.SSLError as error:
                    outcomes.append(("rejected", str(error)))
                finally:
                    connection.close()
            except ConnectionResetError:
                outcomes.append(("closed", b""))
            except Exception as error:
                outcomes.append(("server-error", str(error)))
        worker = threading.Thread(target=serve, daemon=True); worker.start()
        peer = Peer("opus")
        try:
            peer.ok(f"TLSREGISTER 127.0.0.1:{port} test-only")
            try:
                peer.wait(lambda line: line.startswith("EVENT 1 0 ") and not line.startswith("EVENT 1 0 0 "))
            except AssertionError:
                print("TLS server outcomes:", outcomes, flush=True)
                sample = subprocess.run(["/usr/bin/sample", str(peer.process.pid), "1", "-file", "/dev/stdout"], capture_output=True, text=True, timeout=8)
                print(sample.stdout[:20000], flush=True)
                raise
            worker.join(timeout=8)
            # PJSIP intentionally completes the TLS handshake so it can surface
            # certificate details, then rejects the SIP transport before sending
            # REGISTER. A TCP reset / empty read is therefore also expected.
            assert outcomes and (outcomes[0][0] in ("rejected", "closed") or outcomes[0] == ("accepted", b"")), outcomes
            assert any(line.startswith("EVENT 5 0 171173 ") for line in peer.transcript), peer.transcript
            print("PASS TLS: native certificate verification error 171173, registration rejected, no SIP bytes sent; no trust exception installed")
        finally:
            peer.stop(); listener.close()
