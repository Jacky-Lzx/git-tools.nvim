"""Drive actual terminal input, including Visual/operator mappings and typing."""
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import shutil
import signal
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
    lazygit_config = directory / "lazygit"
    lazygit_config.mkdir()
    env["GIT_TOOLS_TEST_LAZYGIT_CONFIG"] = str(lazygit_config)
    env["SELECTION_TOOLS_DIR"] = os.environ.get("SELECTION_TOOLS_DIR", str(root.parent / "selection-tools.nvim"))
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
            send("\x1b[24~")
            drain(0.12)
            if state.exists():
                value = json.loads(state.read_text())
                if predicate(value):
                    return value
        raise AssertionError(message + "\n" + (json.dumps(value, ensure_ascii=False) if state.exists() else "No snapshot") + "\n" + transcript.decode(errors="replace")[-1000:])

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
        if (Path(env["SELECTION_TOOLS_DIR"]) / "lua/selection_tools/init.lua").exists():
            send(":lua _G.git_tools_test_picker=require('git_tools').changes({kind='unstaged'})\r")
            drain(0.2)
            send("sample")
            snapshot(lambda value: value.get("picker", {}).get("query") == "sample" and value["picker"].get("hunk"), "Hunk picker filter did not update")
            send("\x1b[14~")  # F4: files
            snapshot(lambda value: value.get("picker", {}).get("hunk") is False and value["picker"]["query"] == "sample", "Grouping lost the query")
            send("\x1b[14~")
            snapshot(lambda value: value.get("picker", {}).get("hunk"), "Hunk grouping did not return")
            send("\x13")  # C-s: stage selected disk hunk
            snapshot(lambda value: value.get("picker", {}).get("count") == 0, "Picker action did not refresh results")
            assert git("show", ":sample.txt").startswith("one\ntwo\n"), "Picker must stage disk rather than unsaved text"
            send("\x03")
            snapshot(lambda value: not value.get("picker") and value["lines"][:2] == ["ONE", "TWO"], "Picker changed the unsaved source")
        if shutil.which("lazygit"):
            send("\x07")
            drain(0.7)
            send("\x1c\x0e")
            terminal = snapshot(lambda value: value.get("lazygit", {}).get("running") and value["filetype"] == "git-tools-lazygit", "Real LazyGit did not open in the float")
            assert terminal["lazygit"]["relative"] == "editor"
            assert any(word in "\n".join(terminal["lines"]).lower() for word in ("lazygit", "files", "commits")), "No LazyGit UI rendered"
            send(":lua require('git_tools').lazygit()\r")
            send("\x1c\x0e")
            snapshot(lambda value: value.get("lazygit", {}).get("job") == terminal["lazygit"]["job"], "Repeated open replaced the LazyGit job")
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 34, 120, 0, 0))
            os.kill(process.pid, signal.SIGWINCH)
            drain(0.2)
            snapshot(lambda value: value.get("lazygit", {}).get("width") == int(118 * 0.9), "Real terminal resize did not update the float")
            send("\x07")
            snapshot(lambda value: value["lines"][0] == "ONE" and not value.get("lazygit"), "Close key did not preserve the source buffer")
            send("\x07")
            drain(0.4)
            send("\x1b")
            send("q")
            drain(0.4)
            send("\x1c\x0e")
            closed = snapshot(lambda value: True, "Cannot inspect LazyGit exit")
            for _ in range(3):
                if not closed.get("lazygit"):
                    break
                send("i")
                send("\x1b")
                send("q")
                drain(0.3)
                send("\x1c\x0e")
                closed = snapshot(lambda value: True, "Cannot inspect LazyGit exit")
            assert not closed.get("lazygit") and closed["lines"][0] == "ONE", "Real LazyGit quit did not close its window: " + json.dumps(closed, ensure_ascii=False)
            print("git TUI: real LazyGit float, repeated open, resize, close/reopen and quit passed")
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
