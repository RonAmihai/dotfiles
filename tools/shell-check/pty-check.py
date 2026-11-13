#!/usr/bin/env python3
"""Usage: pty-check.py SHELL — runs SHELL interactively in a pseudo-terminal: types commands, reads its config a second time, runs reload, and fails on a crash or an error line"""
import os
import pty
import re
import select
import sys
import time

shell = sys.argv[1]
rc = "~/.zshrc" if os.path.basename(shell) == "zsh" else "~/.bashrc"
errors = re.compile(r"error|not found|not provided|permission denied|segmentation|no such file", re.IGNORECASE)
ansi = re.compile(r"\x1b(\[[0-9;?]*[ -/]*[@-~]|\][^\x07]*\x07|[()][A-Z0-9])")

pid, fd = pty.fork()
if pid == 0:
    os.execv(shell, [shell, "-i"])

output = b""


def wait_for(marker, timeout=40):
    global output
    end = time.time() + timeout
    while time.time() < end:
        ready, _, _ = select.select([fd], [], [], 0.5)
        if not ready:
            continue
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            return False
        if not chunk:
            return False
        output += chunk
        if marker.encode() in output:
            return True
    return False


def step(line, number):
    """Types a line, then an echo whose output differs from its typed text, and waits for that output"""
    if line:
        os.write(fd, (line + "\r").encode())
    os.write(fd, f"echo pty-$((1+{number}))\r".encode())
    return wait_for(f"pty-{1 + number}")


def text():
    return ansi.sub("", output.decode("utf-8", "replace"))


# Deferred plugins load after the first prompt, so the steps after the pause run through their key handlers.
# A newer prompt theme, as after an apply, makes the second read rebuild the prompt cache.
theme = "~/.config/oh-my-posh/cli-theme.omp.json"
steps = [("", 10), (None, 0), (f"touch {theme} 2>/dev/null; source {rc}", 20), ("reload", 30)]
for line, number in steps:
    if line is None:
        time.sleep(2)
        continue
    if not step(line, number):
        print(f"the shell stopped answering after: {line or 'its start'}")
        print(text()[-1500:])
        sys.exit(1)

os.write(fd, b"exit\r")
time.sleep(0.5)
bad = [line for line in text().splitlines() if errors.search(line)]
if bad:
    print("the shell printed errors:")
    print("\n".join(bad[:15]))
    sys.exit(1)
