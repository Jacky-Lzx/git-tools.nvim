"""Drive actual terminal input, including Visual/operator mappings and typing."""
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import shutil
import struct
import subprocess
import tempfile
import termios
import time

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="git-tools-tui-") as temporary:
    directory = Path(temporary)
    fixture = directory / "repo"
    fixture.mkdir()

    def git(*args):
        return subprocess.check_output(
            ["git", "-C", str(fixture), "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", *args],
            stderr=subprocess.STDOUT,
        ).decode()

    git("init", "-q")
    git("config", "user.name", "Fixture")
    git("config", "user.email", "fixture@example.invalid")
    (fixture / "sample.txt").write_text("one\ntwo\nthree\nfour\nfive\nsix\n")
    git("add", ".")
    git("commit", "-qm", "initial")
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 140, 0, 0))
    state = directory / "state.json"
    env = dict(os.environ, TERM="xterm-256color", GIT_TOOLS_ROOT=str(root), GIT_TOOLS_TUI_STATE=str(state),
               XDG_STATE_HOME=str(directory / "state"), XDG_CACHE_HOME=str(directory / "cache"), NVIM_LOG_FILE=str(directory / "nvim.log"))
    process = subprocess.Popen([shutil.which("nvim"), "-n", "-i", "NONE", "-u", str(root / "tests/tui.lua"), str(fixture / "sample.txt")],
                               stdin=slave, stdout=slave, stderr=slave, env=env)
    transcript = bytearray()

    def drain(duration=0.08):
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            if select.select([master], [], [], min(0.02, max(0, deadline - time.monotonic())))[0]:
                try:
                    transcript.extend(os.read(master, 65536))
                except OSError:
                    break

    def send(text):
        os.write(master, text.encode())
        drain()

    def snapshot(predicate, message):
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            state.unlink(missing_ok=True)
            send("\x1b:lua git_tools_snapshot()\r")
            drain(0.12)
            if state.exists():
                value = json.loads(state.read_text())
                if predicate(value):
                    return value
        raise AssertionError(message + "\n" + transcript.decode(errors="replace")[-4000:])

    try:
        drain(0.6)
        snapshot(lambda value: value["index"] == "one\ntwo\nthree\nfour\nfive\nsix\n", "Initial index did not load")
        send(" to")
        snapshot(lambda value: value["overlay"], "First overlay key did not enable")
        send("gg0i")
        for char in "continuous typing ":
            os.write(master, char.encode())
            drain(0.006)
        send("\x1b")
        snapshot(lambda value: value["lines"][0] == "continuous typing one" and value["marks"] > 0, "Typing/overlay did not refresh")
        send("gg0CONE\x1bj0CTWO\x1b")
        snapshot(lambda value: value["lines"][:2] == ["ONE", "TWO"] and value["hunks"] > 0, "Replacement edits lost")
        send("ggjV ggs\x1b")
        snapshot(lambda value: value["index"].startswith("one\nTWO\n"), "Visual mapping staged the wrong lines")
        assert git("show", ":sample.txt").startswith("one\nTWO\n")
        assert (fixture / "sample.txt").read_text().startswith("one\ntwo\n")
        send("ggdih")
        snapshot(lambda value: value["lines"][0] == "TWO", "Operator-pending dih failed")
        send("u")
        snapshot(lambda value: value["lines"][0] == "ONE", "Hunk deletion did not undo")
        assert len(transcript) > 500, "No real terminal frames captured"
        print("git TUI: continuous typing, first overlay, Visual staging, dih and undo passed")
    finally:
        send("\x1b:qa!\r")
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        os.close(master)
        os.close(slave)
