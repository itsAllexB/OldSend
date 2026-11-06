#!/usr/bin/env python3
"""Send files to a LocalSend receiver the way LocalSend's own client does (protocol v2).

    python localsend_send.py <ip> [--chunked] [--port 53317] [--timeout 180] <file> [file...]

Each request gets its own TLS connection, as with a real sender once the receiver answers
"Connection: close". --chunked streams uploads with Transfer-Encoding: chunked instead of
Content-Length. Prints one line per request and a final "RESULT ok=<n> failed=<n> seconds=<s>";
the exit code is 0 only if every file was accepted and uploaded.

A dropped connection shows here as "NO RESPONSE": the same failure a desktop LocalSend reports
as hyper::Error(IncompleteMessage).
"""
import argparse
import hashlib
import http.client
import json
import mimetypes
import os
import socket
import ssl
import sys
import time
import uuid


def tls_context():
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    context.set_ciphers("DEFAULT:@SECLEVEL=0")
    return context


class Sender:
    def __init__(self, ip, port, timeout, chunked):
        self.ip, self.port, self.timeout, self.chunked = ip, port, timeout, chunked
        self.context = tls_context()

    def request(self, path, body, content_type="application/json"):
        """(status, data), or (None, reason) if the connection died before a whole response."""
        connection = http.client.HTTPSConnection(self.ip, self.port, context=self.context,
                                                 timeout=self.timeout)
        try:
            connection.request("POST", path, body=body,
                               headers={"Content-Type": content_type,
                                        "Content-Length": str(len(body))})
            response = connection.getresponse()
            return response.status, response.read()
        except (http.client.HTTPException, OSError, socket.timeout) as error:
            return None, repr(error)
        finally:
            connection.close()

    def upload(self, path, name, content_type):
        """Streams one file, like a real client: never the whole file in memory."""
        size = os.path.getsize(name)
        connection = http.client.HTTPSConnection(self.ip, self.port, context=self.context,
                                                 timeout=self.timeout)
        try:
            connection.putrequest("POST", path, skip_accept_encoding=True)
            connection.putheader("Content-Type", content_type)
            if self.chunked:
                connection.putheader("Transfer-Encoding", "chunked")
            else:
                connection.putheader("Content-Length", str(size))
            connection.endheaders()
            with open(name, "rb") as file:
                while True:
                    block = file.read(256 * 1024)
                    if not block:
                        break
                    if self.chunked:
                        connection.send(b"%x\r\n" % len(block) + block + b"\r\n")
                    else:
                        connection.send(block)
            if self.chunked:
                connection.send(b"0\r\n\r\n")
            response = connection.getresponse()
            return response.status, response.read()
        except (http.client.HTTPException, OSError, socket.timeout) as error:
            return None, repr(error)
        finally:
            connection.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("ip")
    parser.add_argument("files", nargs="+")
    parser.add_argument("--port", type=int, default=53317)
    parser.add_argument("--timeout", type=float, default=180)
    parser.add_argument("--chunked", action="store_true")
    parser.add_argument("--alias", default="OldSend test sender")
    arguments = parser.parse_args()

    sender = Sender(arguments.ip, arguments.port, arguments.timeout, arguments.chunked)
    info = {"alias": arguments.alias, "version": "2.1", "deviceModel": "Python",
            "deviceType": "desktop",
            "fingerprint": hashlib.sha256(arguments.alias.encode()).hexdigest(),
            "port": arguments.port, "protocol": "https", "download": False}
    metadata, paths = {}, {}
    for path in arguments.files:
        identifier = uuid.uuid4().hex
        paths[identifier] = path
        metadata[identifier] = {
            "id": identifier, "fileName": os.path.basename(path), "size": os.path.getsize(path),
            "fileType": mimetypes.guess_type(path)[0] or "application/octet-stream"}

    started = time.time()
    status, data = sender.request("/api/localsend/v2/prepare-upload",
                                  json.dumps({"info": info, "files": metadata}).encode())
    print("prepare-upload", status if status is not None else "NO RESPONSE", data[:160], flush=True)
    if status != 200:
        print(f"RESULT ok=0 failed={len(paths)} seconds={time.time() - started:.1f}")
        return 1

    answer = json.loads(data)
    session = answer["sessionId"]
    tokens = answer["files"]
    ok = failed = 0
    for identifier, path in paths.items():
        token = tokens.get(identifier)
        if token is None:
            print("skipped", os.path.basename(path), flush=True)
            failed += 1
            continue
        file_started = time.time()
        status, data = sender.upload(
            f"/api/localsend/v2/upload?sessionId={session}&fileId={identifier}&token={token}",
            path, metadata[identifier]["fileType"])
        seconds = time.time() - file_started
        print("upload", os.path.basename(path), status if status is not None else "NO RESPONSE",
              f"{seconds:.1f}s", data[:120] if status != 200 else "", flush=True)
        if status == 200:
            ok += 1
        else:
            failed += 1
    print(f"RESULT ok={ok} failed={failed} seconds={time.time() - started:.1f}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
