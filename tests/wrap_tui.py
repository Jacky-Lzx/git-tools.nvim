"""Check real Alt+Z input, visible continuation rows, and focus preservation."""
import fcntl
import json
import os
from pathlib import Path
import pty
import re
import select
import signal
import struct
import subprocess
import tempfile
import termios
import time

root = Path(__file__).resolve().parents[1]
configured = os.environ.get("GIT_TOOLS_CONFIGURED") == "1"
layouts = (os.environ["GIT_TOOLS_LAYOUT"],) if "GIT_TOOLS_LAYOUT" in os.environ else ("unified", "top_bottom", "side_by_side")
for layout in layouts:
    with tempfile.TemporaryDirectory(prefix="diff-wrap-tui-") as temporary:
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 56, 140, 0, 0))
        env = dict(os.environ, TERM="xterm-256color", GIT_TOOLS_ROOT=str(root),
                   GIT_TOOLS_LAYOUT=layout, GIT_TOOLS_TUI_DIR=temporary,
                   XDG_STATE_HOME=temporary + "/state", XDG_CACHE_HOME=temporary + "/cache",
                   NVIM_LOG_FILE=temporary + "/nvim.log", NVIM_SMOKE_TEST="1",
                   NVIM_LAZY_LOCKFILE=temporary + "/lazy-lock.json")
        init = str(Path.home() / ".config/nvim/init.lua") if configured else "NONE"
        child = subprocess.Popen(["nvim", "--cmd", "let g:loaded_wakatime=1", "-u", init, "-i", "NONE", "-n", "-c",
                                  "luafile " + str(root / "tests/wrap_tui.lua")],
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

        def snapshot(predicate):
            path = Path(temporary) / "snapshot.json"
            value = None
            for _ in range(20):
                path.unlink(missing_ok=True)
                send("\x1b[24~")
                drain(0.12)
                if path.exists():
                    value = json.loads(path.read_text())
                    if predicate(value):
                        assert value["source"] == [""], "Source buffer was changed"
                        assert not value["error"], value["error"]
                        return value
            raise AssertionError(json.dumps(value, ensure_ascii=False) + "\n" + transcript.decode(errors="replace")[-1500:])

        def ready(value):
            return "picker" in value and value["picker"]["focus"] and value["mode"] == "i"

        def visible_tail(screen, needle):
            if layout == "side_by_side":
                side = 0 if needle.startswith("OLD") else 1
                rows = [line.split(" │ ", 1)[side] for line in screen.splitlines() if " │ " in line]
                screen = "".join(re.sub(r"^\s*(?:\d+\s+)?[+-]\s?", "", line).rstrip() for line in rows)
            return needle in "".join(screen.split())

        try:
            # Let configured startup notifications expire before reading cells.
            drain(6 if configured else 0.3)
            send("\x1b[17~")  # F6
            first = snapshot(ready)
            assert not visible_tail(first["picker"]["screen"], "NEW_END")
            send("\x1bz")  # actual Alt+Z from Insert mode in picker input
            wrapped = snapshot(lambda v: ready(v) and v["picker"]["wrap"])
            assert visible_tail(wrapped["picker"]["screen"], "OLD_END") and visible_tail(wrapped["picker"]["screen"], "NEW_END"), json.dumps(wrapped, ensure_ascii=False)
            assert wrapped["picker"]["query"] == "" and wrapped["picker"]["buf"] == first["picker"]["buf"]
            send("\x1bz")
            unwrapped = snapshot(lambda v: ready(v) and not v["picker"]["wrap"])
            assert not visible_tail(unwrapped["picker"]["screen"], "NEW_END")
            send("\x1bz\x1b[B")
            moved = snapshot(lambda v: ready(v) and v["picker"]["selected"] == "two")
            assert moved["picker"]["wrap"] and visible_tail(moved["picker"]["screen"], "NEW_END")
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 56, 110, 0, 0))
            os.kill(child.pid, signal.SIGWINCH)
            resized = snapshot(lambda v: ready(v) and v["picker"]["width"] < moved["picker"]["width"])
            assert resized["picker"]["wrap"] and visible_tail(resized["picker"]["screen"], "NEW_END"), json.dumps(resized, ensure_ascii=False)
            send("\x1b[19~")  # F8: focus the actual diff buffer in Normal mode
            snapshot(lambda v: "picker" in v and not v["picker"]["focus"] and v["mode"] == "n")
            send("\x1bz")
            snapshot(lambda v: "picker" in v and not v["picker"]["wrap"] and v["mode"] == "n")
            send("\x1b[20~")  # F9: input
            snapshot(ready)
            send("\x03")  # C-c: close
            snapshot(lambda v: "picker" not in v and v["origin"])
            send("\x1b[21~")  # F10: native comparison tab
            snapshot(lambda v: "view" in v)
            send("\x1bz")
            comparison = snapshot(lambda v: v.get("view", {}).get("wrap") == [True, True])
            assert all("_END" in text for text in comparison["view"]["screen"])
            send("\x17h\x1bz")  # switch pane, then toggle both panes
            snapshot(lambda v: v.get("view", {}).get("wrap") == [False, False])
            send("q")
            snapshot(lambda v: "view" not in v and v["origin"])
            print("Diff wrap TUI (" + layout + ")" + (" (configured)" if configured else "") + ": Insert/Normal Alt+Z, visible Unicode tails, selection, resize, focus and comparison panes passed")
        finally:
            send("\x1b:qa!\r")
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
            os.close(master)
            os.close(slave)
