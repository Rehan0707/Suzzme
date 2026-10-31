#!/usr/bin/env python3
"""Loopback-only TLS fixtures. No keychain, hosts, proxy, or system trust changes."""

import argparse
import errno
import json
import os
from pathlib import Path
import re
import select
import signal
import socket
import ssl
import subprocess
import threading
import time


def verify_release_source(package):
    """The test factory must have a positive dedicated compilation guard."""
    found = 0
    for source in (package / "Sources").rglob("*.swift"):
        stack = []
        for number, line in enumerate(source.read_text().splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith("#if "):
                stack.append(stripped[4:].strip() == "WATCHED_TRANSPORT_CONNECTION_TESTS")
            elif stripped.startswith("#elseif ") or stripped == "#else":
                if stack:
                    stack[-1] = False
            elif stripped == "#endif":
                if stack:
                    stack.pop()
            elif not stripped.startswith("//"):
                if "func connectionTestClient(" in line:
                    found += 1
                if re.search(r"\b(connectionTestClient|connectionTestRoot|rootCertificateDER|testTrust)\b", line) and not any(stack):
                    raise SystemExit(f"FAIL test factory/root capability is not test-guarded: {source}:{number}")
    if found != 1:
        raise SystemExit(f"FAIL expected exactly one guarded connection test factory, found {found}")
    print("PASS connection test factory and root storage have dedicated positive compilation guards")


class Fixture:
    def __init__(self, output):
        self.output = output.resolve()
        self.output.mkdir(parents=True, exist_ok=True)
        os.chmod(self.output, 0o700)
        self.events_path = self.output / "events.jsonl"
        self.events_path.touch(mode=0o600)
        self.lock = threading.Lock()
        self.stop = threading.Event()
        self.listeners = []
        self.held_sockets = []
        self.next_id = 0
        self.audit = self.listener()
        self.decoy = self.listener()
        self.tls_stall = self.listener()
        self.tls = self.listener()
        self.backlog = self.listener(backlog=1)
        self.prepare_certificates(self.audit.getsockname()[1])
        self.contexts = {name: self.context(name) for name in ["valid", "expired", "untrusted", "aia"]}
        self.sni_names = {}
        self.contexts["valid"].set_servername_callback(self.choose_certificate)

    def listener(self, backlog=32):
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(("127.0.0.1", 0))
        listener.listen(backlog)
        listener.settimeout(0.2)
        self.listeners.append(listener)
        return listener

    def record(self, kind, **values):
        with self.lock:
            with self.events_path.open("a") as log:
                log.write(json.dumps({"event": kind, "time": time.monotonic(), **values}, sort_keys=True) + "\n")
                log.flush()

    def openssl(self, *arguments):
        result = subprocess.run(["/usr/bin/openssl", *map(str, arguments)], cwd=self.output,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
        with (self.output / "certificate-generation.log").open("ab") as log:
            log.write(result.stdout)
        if result.returncode:
            raise RuntimeError(f"openssl failed ({result.returncode}); see certificate-generation.log")

    def prepare_certificates(self, audit_port):
        # All identities and keys are generated for this run and remain under the ignored output folder.
        ca_config = self.output / "root-ca.cnf"
        ca_config.write_text("[req]\ndistinguished_name=dn\nx509_extensions=root\n[dn]\n[root]\n"
                             "basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\nsubjectKeyIdentifier=hash\n")
        for ca in ["root", "other-root"]:
            self.openssl("req", "-new", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2",
                         "-config", ca_config, "-subj", f"/CN=Suzme isolated {ca}", "-keyout", f"{ca}.key", "-out", f"{ca}.pem")
        self.openssl("x509", "-in", "root.pem", "-outform", "DER", "-out", "root.der")
        self.make_leaf("intermediate", "Suzme isolated intermediate", "root", ca=True)
        self.openssl("x509", "-in", "intermediate.pem", "-outform", "DER", "-out", "intermediate.der")
        self.make_leaf("valid", "watched.fixture.invalid", "root")
        self.make_leaf("untrusted", "untrusted.fixture.invalid", "other-root")
        self.make_leaf("aia", "aia.fixture.invalid", "intermediate", audit_port=audit_port)
        self.make_leaf("expired", "expired.fixture.invalid", "root", expired=True)
        for path in self.output.glob("*.key"):
            os.chmod(path, 0o600)

    def make_leaf(self, name, hostname, issuer, ca=False, audit_port=None, expired=False):
        extension = "basicConstraints=critical,CA:TRUE,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign\n" if ca else (
            f"basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\n"
            f"extendedKeyUsage=serverAuth\nsubjectAltName=DNS:{hostname}\n")
        if audit_port is not None:
            extension += f"authorityInfoAccess=caIssuers;URI:http://127.0.0.1:{audit_port}/intermediate.der\n"
        ext_path = self.output / f"{name}.ext"
        ext_path.write_text(extension)
        self.openssl("req", "-new", "-newkey", "rsa:2048", "-nodes", "-subj", f"/CN={hostname}",
                     "-keyout", f"{name}.key", "-out", f"{name}.csr")
        if not expired:
            self.openssl("x509", "-req", "-in", f"{name}.csr", "-CA", f"{issuer}.pem", "-CAkey", f"{issuer}.key",
                         "-CAcreateserial", "-days", "1", "-sha256", "-extfile", ext_path, "-out", f"{name}.pem")
        else:
            # `openssl ca` supports explicit past validity without changing the machine clock.
            (self.output / "index.txt").touch()
            (self.output / "serial.txt").write_text("1000\n")
            config = self.output / "expired-ca.cnf"
            config.write_text(
                "[ca]\ndefault_ca=isolated\n[isolated]\n"
                f"database={self.output}/index.txt\nserial={self.output}/serial.txt\nnew_certs_dir={self.output}\n"
                f"certificate={self.output}/{issuer}.pem\nprivate_key={self.output}/{issuer}.key\n"
                "default_md=sha256\npolicy=policy\nx509_extensions=leaf\n[policy]\ncommonName=supplied\n[leaf]\n" + extension)
            self.openssl("ca", "-batch", "-config", config, "-startdate", "20200101000000Z", "-enddate", "20200102000000Z",
                         "-in", f"{name}.csr", "-out", f"{name}.pem", "-notext")

    def context(self, name):
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.set_alpn_protocols(["http/1.1"])
        # Deliberately send no intermediate for the private AIA test.
        context.load_cert_chain(self.output / f"{name}.pem", self.output / f"{name}.key")
        return context

    def choose_certificate(self, connection, hostname, _context):
        with self.lock:
            self.sni_names[id(connection)] = hostname
        if hostname == "expired.fixture.invalid":
            connection.context = self.contexts["expired"]
        elif hostname == "untrusted.fixture.invalid":
            connection.context = self.contexts["untrusted"]
        elif hostname == "aia.fixture.invalid":
            connection.context = self.contexts["aia"]

    def accept(self, listener, mode):
        while not self.stop.is_set():
            try:
                connection, peer = listener.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            with self.lock:
                self.next_id += 1
                identifier = self.next_id
            self.record("accepted", id=identifier, mode=mode, port=listener.getsockname()[1], peer=list(peer))
            threading.Thread(target=self.handle, args=(connection, identifier, mode), daemon=True).start()

    def await_peer_close(self, connection, identifier, seconds=4):
        deadline = time.monotonic() + seconds
        connection.settimeout(0.1)
        while not self.stop.is_set() and time.monotonic() < deadline:
            try:
                data = connection.recv(4096)
                if not data:
                    self.record("peer_closed", id=identifier)
                    return
            except socket.timeout:
                continue
            except (OSError, ssl.SSLError):
                self.record("peer_closed", id=identifier)
                return
        self.record("peer_close_timeout", id=identifier)

    def handle(self, connection, identifier, mode):
        try:
            connection.settimeout(3)
            if mode in ["decoy", "audit"]:
                self.record("unexpected_connection", id=identifier, mode=mode)
                if mode == "audit":
                    connection.recv(8192)
                    data = (self.output / "intermediate.der").read_bytes()
                    connection.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: " + str(len(data)).encode() + b"\r\n\r\n" + data)
                return
            if mode == "tls_stall":
                self.await_peer_close(connection, identifier)
                return
            connection = self.contexts["valid"].wrap_socket(connection, server_side=True, do_handshake_on_connect=False)
            try:
                connection.do_handshake()
            except (OSError, ssl.SSLError) as error:
                self.record("tls_failed", id=identifier, error=type(error).__name__)
                return
            with self.lock:
                sni = self.sni_names.pop(id(connection), None)
            self.record("tls_ready", id=identifier, sni=sni, alpn=connection.selected_alpn_protocol())
            data = b""
            while b"\r\n\r\n" not in data and len(data) < 16384:
                piece = connection.recv(4096)
                if not piece:
                    return
                data += piece
            header, _, body = data.partition(b"\r\n\r\n")
            lines = header.decode("ascii").split("\r\n")
            method, path, version = lines[0].split(" ")
            headers = {line.split(":", 1)[0].lower(): line.split(":", 1)[1].strip() for line in lines[1:]}
            self.record("request", id=identifier, method=method, path=path, version=version, headers=headers, bodyBytes=len(body), sni=sni)
            if path in ["/slow-head", "/cancel-head"]:
                self.await_peer_close(connection, identifier)
                return
            if path in ["/slow-body", "/cancel-body"]:
                connection.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nx")
                self.await_peer_close(connection, identifier)
                return
            response = self.response(path)
            if path == "/fragmented-headers":
                for offset in range(0, len(response), 97):
                    connection.sendall(response[offset:offset + 97])
                    time.sleep(0.001)
            else:
                connection.sendall(response)
            if path == "/close-delimited":
                # A successful EOF-delimited response needs a TLS close_notify,
                # rather than an intentionally truncated TCP close.
                connection.settimeout(1)
                try:
                    connection = connection.unwrap()
                except (OSError, ssl.SSLError):
                    pass
        except (OSError, ssl.SSLError) as error:
            self.record("connection_error", id=identifier, error=type(error).__name__)
        finally:
            try:
                connection.close()
            except OSError:
                pass
            self.record("closed", id=identifier, mode=mode)

    def response(self, path):
        normal = b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello"
        if path.startswith("/status/"):
            status = int(path.rsplit("/", 1)[1])
            return f"HTTP/1.1 {status} Fixture\r\nLocation: https://target.fixture.invalid/next\r\nSet-Cookie: never=store\r\nContent-Length: 999\r\n\r\n".encode()
        if path.startswith("/mime/"):
            mime = {"html": "text/html; charset=utf-8", "plain": "text/plain", "xhtml": "application/xhtml+xml", "case": "TEXT/HTML; Charset=UTF-8"}[path.rsplit("/", 1)[1]]
            return normal.replace(b"text/plain", mime.encode())
        if path in ["/headers-too-large", "/fragmented-headers"]:
            return normal.replace(b"Connection: close\r\n", b"X-Padding: " + b"p" * 9000 + b"\r\n")
        if path == "/whitespace-too-large":
            return normal.replace(b"Connection: close\r\n", b"X-Padding:" + b" " * 9000 + b"p\r\n")
        if path == "/status-line-too-large":
            return normal.replace(b"200 OK", b"200 " + b"x" * 9000)
        if path == "/header-exact-limit":
            prefix = b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 5\r\nX-Padding: "
            return prefix + b"p" * (8192 - len(prefix) - 4) + b"\r\n\r\nhello"
        if path == "/body-at-limit":
            return b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 524288\r\n\r\n" + b"b" * 524288
        if path == "/body-over-limit":
            return b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n" + b"b" * 524289
        if path == "/advertised-body-over-limit":
            return normal.replace(b"Content-Length: 5", b"Content-Length: 524289")
        if path == "/close-delimited":
            return normal.replace(b"Content-Length: 5\r\n", b"")
        if path in ["/transfer-chunked", "/transfer-trailers"]:
            ending = b"5\r\nhello\r\n0\r\n\r\n" if path == "/transfer-chunked" else b"5\r\nhello\r\n0\r\nX-Trailer: hidden\r\n\r\n"
            return b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nTransfer-Encoding: chunked\r\n\r\n" + ending
        replacements = {
            "/malformed-status": (b"HTTP/1.1 200 OK", b"NOT-HTTP"),
            "/malformed-header": (b"Connection: close", b"Header Without Colon"),
            "/duplicate-length": (b"Content-Length: 5", b"Content-Length: 5\r\nContent-Length: 5"),
            "/conflicting-length": (b"Content-Length: 5", b"Content-Length: 5\r\nContent-Length: 6"),
            "/duplicate-type": (b"Content-Type: text/plain", b"Content-Type: text/plain\r\nContent-Type: text/html"),
            "/duplicate-location": (b"Connection: close", b"Location: /one\r\nLocation: /two"),
            "/unsupported-mime": (b"text/plain", b"image/png"),
            "/mime-prefix": (b"text/plain", b"text/plaintext"),
            "/missing-mime": (b"Content-Type: text/plain\r\n", b""),
            "/content-encoding": (b"Connection: close", b"Content-Encoding: gzip"),
            "/identity-encoding": (b"Connection: close", b"Content-Encoding: identity"),
            "/transfer-identity": (b"Content-Length: 5", b"Transfer-Encoding: identity"),
            "/transfer-gzip": (b"Content-Length: 5", b"Transfer-Encoding: gzip"),
            "/informational": (b"HTTP/1.1 200 OK", b"HTTP/1.1 100 Continue"),
            "/upgrade": (b"HTTP/1.1 200 OK", b"HTTP/1.1 101 Switching Protocols"),
            "/truncated-body": (b"hello", b"he"),
        }
        if path in replacements:
            return normal.replace(*replacements[path])
        return normal

    def saturate_backlog(self):
        # Kernels differ: Darwin resets excess loopback connects immediately,
        # while some kernels leave SYNs pending. Check SO_ERROR rather than
        # mistaking every writable socket for a successful TCP handshake.
        address = self.backlog.getsockname()
        for _ in range(16):
            connection = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            connection.setblocking(False)
            result = connection.connect_ex(address)
            self.held_sockets.append(connection)
            if result not in (0, errno.EINPROGRESS, errno.EWOULDBLOCK):
                raise RuntimeError(f"Unexpected backlog connect result: {result}")
            _, writable, _ = select.select([], [connection], [], 0.08)
            if not writable:
                return {"outcome": "pending", "socketError": 0}
            error = connection.getsockopt(socket.SOL_SOCKET, socket.SO_ERROR)
            if error in (errno.ECONNRESET, errno.ECONNREFUSED):
                return {"outcome": "reset", "socketError": error}
            if error:
                raise RuntimeError(f"Unexpected backlog socket error: {error}")
        raise RuntimeError("Could not establish an isolated full TCP backlog")

    def run(self):
        for listener, mode in [(self.tls, "tls"), (self.tls_stall, "tls_stall"), (self.audit, "audit"), (self.decoy, "decoy")]:
            threading.Thread(target=self.accept, args=(listener, mode), daemon=True).start()
        backlog = self.saturate_backlog()
        self.record("backlog_fixture", **backlog)
        manifest = {"hostname": "watched.fixture.invalid", "address": "127.0.0.1", "port": self.tls.getsockname()[1],
                    "tlsStallPort": self.tls_stall.getsockname()[1], "backlogPort": self.backlog.getsockname()[1],
                    "backlogOutcome": backlog["outcome"], "backlogSocketError": backlog["socketError"], "decoyPort": self.decoy.getsockname()[1], "auditPort": self.audit.getsockname()[1],
                    "rootDERPath": str(self.output / "root.der"), "eventsPath": str(self.events_path)}
        temporary = self.output / "fixture.json.tmp"
        temporary.write_text(json.dumps(manifest, indent=2) + "\n")
        temporary.replace(self.output / "fixture.json")
        self.record("ready", ports=[item.getsockname()[1] for item in self.listeners])
        self.stop.wait()
        for connection in self.held_sockets + self.listeners:
            connection.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path)
    parser.add_argument("--verify-release-source", type=Path)
    arguments = parser.parse_args()
    if arguments.verify_release_source:
        verify_release_source(arguments.verify_release_source)
        return
    if not arguments.output:
        parser.error("--output is required to start fixtures")
    fixture = Fixture(arguments.output)
    signal.signal(signal.SIGTERM, lambda *_: fixture.stop.set())
    signal.signal(signal.SIGINT, lambda *_: fixture.stop.set())
    fixture.run()


if __name__ == "__main__":
    main()
