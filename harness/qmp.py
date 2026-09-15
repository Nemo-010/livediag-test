#!/usr/bin/env python3
"""Drive a QEMU guest over QMP: press keys and save screen dumps.

The harness uses this instead of a real display.  QEMU renders the guest
into its own framebuffer and ``screendump`` hands us PNG (or PPM) frames,
which is enough to build a video of the desktop and the tests it runs.
"""

import argparse
import json
import os
import socket
import sys
import time


class QMPError(Exception):
    pass


class QMP:
    def __init__(self, path, timeout=60):
        deadline = time.time() + timeout
        self.sock = None
        self.buf = b""
        while time.time() < deadline:
            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.connect(path)
                self.sock = s
                break
            except (FileNotFoundError, ConnectionRefusedError, OSError):
                time.sleep(0.5)
        if self.sock is None:
            raise SystemExit(f"qmp: could not connect to {path} after {timeout}s")
        self._read_message()  # greeting
        self.execute("qmp_capabilities")

    def _read_message(self):
        while b"\n" not in self.buf:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise SystemExit("qmp: connection closed")
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        return json.loads(line)

    def execute(self, command, **arguments):
        message = {"execute": command}
        if arguments:
            message["arguments"] = arguments
        self.sock.sendall(json.dumps(message).encode() + b"\n")
        while True:
            reply = self._read_message()
            if "event" in reply:
                continue
            if "error" in reply:
                raise QMPError(reply["error"])
            return reply.get("return")

    def send_key(self, key):
        self.execute("send-key", keys=[{"type": "qcode", "data": key}])

    def screendump(self, path):
        """Save a frame and return the path actually written."""
        try:
            self.execute("screendump", filename=path, format="png")
            return path
        except QMPError:
            ppm = path[:-4] + ".ppm" if path.endswith(".png") else path + ".ppm"
            self.execute("screendump", filename=ppm)
            return ppm


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sock", required=True)
    parser.add_argument("--frames-dir", required=True)
    parser.add_argument("--duration", type=float, default=360.0)
    parser.add_argument("--fps", type=float, default=2.0)
    parser.add_argument("--key-start", type=float, default=35.0,
                        help="seconds before the first key is sent")
    parser.add_argument("--key-interval", type=float, default=3.0)
    parser.add_argument("--stop-file", default=None,
                        help="stop early when this file appears")
    args = parser.parse_args()

    os.makedirs(args.frames_dir, exist_ok=True)
    qmp = QMP(args.sock)

    interval = 1.0 / args.fps
    start = time.time()
    next_frame = start
    next_key = start + args.key_start
    index = 0
    extension = "png"

    while True:
        now = time.time()
        if now - start >= args.duration:
            break
        if args.stop_file and os.path.exists(args.stop_file):
            break

        if now >= next_frame:
            name = os.path.join(args.frames_dir,
                                f"frame{index:06d}.{extension}")
            written = qmp.screendump(name)
            extension = written.rsplit(".", 1)[-1]
            index += 1
            next_frame += interval
            if index % 30 == 0:
                print(f"qmp: {index} frames", flush=True)

        if now >= next_key:
            try:
                qmp.send_key("ret")
            except QMPError as exc:
                print(f"qmp: key failed: {exc}", file=sys.stderr, flush=True)
            next_key += args.key_interval

        time.sleep(0.05)

    # One last frame so the video ends on the final screen.
    try:
        final = os.path.join(args.frames_dir, f"frame{index:06d}.{extension}")
        qmp.screendump(final)
        index += 1
    except QMPError:
        pass

    print(f"qmp: captured {index} frame(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
