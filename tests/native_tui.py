"""Exercise native diff frames through real terminal input and rendered cells."""
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import tempfile
import termios
import time

root = Path(__file__).resolve().parents[1]
layout = os.environ.get("GIT_TOOLS_LAYOUT", "unified")
side_by_side = layout == "side_by_side"
top_bottom = layout == "top_bottom"
configured = os.environ.get("GIT_TOOLS_CONFIGURED") == "1"
wide_columns = 220 if configured and side_by_side else 140
wide_rows = 52 if top_bottom else 40
with tempfile.TemporaryDirectory(prefix="native-diff-tui-") as temporary:
    directory = Path(temporary)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", wide_rows, wide_columns, 0, 0))
    env = dict(os.environ, TERM="xterm-256color", GIT_TOOLS_ROOT=str(root),
               GIT_TOOLS_TUI_DIR=temporary, XDG_STATE_HOME=temporary + "/state",
               XDG_CACHE_HOME=temporary + "/cache", NVIM_LOG_FILE=temporary + "/nvim.log",
               NVIM_SMOKE_TEST="1", NVIM_LAZY_LOCKFILE=temporary + "/lazy-lock.json")
    init = str(Path.home() / ".config/nvim/init.lua") if configured else "NONE"
    child = subprocess.Popen(["nvim", "--cmd", "let g:loaded_wakatime=1", "-u", init, "-i", "NONE", "-n", "-c", "luafile " + str(root / "tests/native_tui.lua")],
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

    def snapshot(predicate, label):
        value = None
        for _ in range(30):
            (directory / "snapshot.json").unlink(missing_ok=True)
            send("\x1b[24~")
            drain(0.12)
            if (directory / "snapshot.json").exists():
                value = json.loads((directory / "snapshot.json").read_text())
                if predicate(value):
                    assert value["unchanged"], "Preview changed the source buffer"
                    return value
        raise AssertionError(label + "\n" + json.dumps(value, ensure_ascii=False) + "\n" + transcript.decode(errors="replace")[-1500:])

    def ready(value):
        return value.get("picker", {}).get("native") and value["picker"]["focus"] and value["mode"] == "i"

    try:
        drain(1.5 if configured else 0.3)
        send("\x1b[17~")  # F6: native provider
        first = snapshot(ready, "Native preview did not open")
        assert first["picker"]["layout"] == layout
        assert "旧名字" in first["picker"]["screen"] and "新名字" in first["picker"]["screen"], json.dumps(first["picker"], ensure_ascii=False)
        if side_by_side:
            title_rows = [line for line in first["picker"]["screen"].splitlines() if "旧名字" in line and "新名字" in line]
            assert len(title_rows) == 1, "Both versions must share a screen row"
            assert "- local" in title_rows[0] and "+ local" in title_rows[0] and " │ " in title_rows[0]
            for old, new in (('    auto("table(%d+)x(%d+)%s", {', '    auto(line_begin, {'),
                             ('    }, line_begin),', '    }, "table(%d+)x(%d+)%s"),')):
                assert any(old in line and new in line for line in first["picker"]["lines"])
            assert sum(first["picker"]["emphasis"].values()) >= 4
        elif top_bottom:
            for text in ('    auto("table(%d+)x(%d+)%s", {', '    auto(line_begin, {',
                         '    }, line_begin),', '    }, "table(%d+)x(%d+)%s"),'):
                assert text in first["picker"]["lines"]
                assert first["picker"]["emphasis"].get(text), "Stacked replacement lost inline emphasis"
        else:
            assert "│ - local" in first["picker"]["screen"] and "│ + local" in first["picker"]["screen"]
            for text in ('    auto("table(%d+)x(%d+)%s", {', '    auto(line_begin, {',
                         '    }, line_begin),', '    }, "table(%d+)x(%d+)%s"),'):
                assert text in first["picker"]["screen"], "Single replacement is not visible: " + text + "\n" + json.dumps(first["picker"], ensure_ascii=False)
                assert first["picker"]["emphasis"].get(text), "Single replacement lost inline emphasis"
        if top_bottom:
            screen = first["picker"]["screen"].splitlines()
            before_row = next(i for i, line in enumerate(screen) if "Before  " in line)
            old_row = next(i for i, line in enumerate(screen) if "旧名字" in line)
            after_row = next(i for i, line in enumerate(screen) if "After  " in line)
            new_row = next(i for i, line in enumerate(screen) if "新名字" in line)
            assert before_row < old_row < after_row < new_row, "Old/new blocks must be stacked"
            assert not any("旧名字" in line and "新名字" in line for line in screen)
            if first["picker"]["height"] < len(first["picker"]["lines"]) + 2:
                send("\x04")  # C-d scrolls the preview while retaining input focus.
                scrolled = snapshot(lambda v: ready(v) and v["picker"]["topline"] > first["picker"]["topline"], "Stacked preview did not scroll")
                assert '    }, "table(%d+)x(%d+)%s"),' in scrolled["picker"]["screen"]
                assert scrolled["picker"]["buf"] == first["picker"]["buf"]
                send("\x15\x15")  # C-u restores the top block.
                snapshot(lambda v: ready(v) and v["picker"]["topline"] == first["picker"]["topline"], "Top block did not return")
            else:
                assert "return title, count -- " + first["picker"]["selected"] in first["picker"]["screen"]
        send("\x1b[18~")  # F7: live theme change
        themed = snapshot(lambda v: ready(v) and v["theme"] != first["theme"], "Theme did not change")
        assert themed["picker"]["buf"] == first["picker"]["buf"] and themed["add"] != first["add"]
        send("".join("\x1b[B\x1b[A" for _ in range(20)) + "\x1b[B")
        moved = snapshot(lambda v: ready(v) and v["picker"]["selected"] != first["picker"]["selected"], "Rapid switching did not move selection")
        assert any("-- " + moved["picker"]["selected"] in line for line in moved["picker"]["lines"])
        assert moved["native_buffers"] == 1, "Rapid switching leaked preview frames"
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 90, 0, 0))
        os.kill(child.pid, signal.SIGWINCH)
        resized = snapshot(lambda v: ready(v) and v["picker"]["width"] < moved["picker"]["width"], "Resize did not update the preview")
        assert resized["picker"]["buf"] == moved["picker"]["buf"]
        if side_by_side:
            title_rows = [line for line in resized["picker"]["screen"].splitlines() if "- loc" in line]
            assert title_rows and "+ loc" in title_rows[0], json.dumps(resized["picker"], ensure_ascii=False)
            assert "…" in resized["picker"]["screen"], "Narrow columns must clip long lines visibly"
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", wide_rows, wide_columns, 0, 0))
            os.kill(child.pid, signal.SIGWINCH)
            restored = snapshot(lambda v: ready(v) and v["picker"]["width"] == moved["picker"]["width"], "Widening did not restore columns")
            assert restored["picker"]["buf"] == moved["picker"]["buf"]
            assert any('    auto("table(%d+)x(%d+)%s", {' in line and '    auto(line_begin, {' in line for line in restored["picker"]["lines"])
        send("zzzz")
        snapshot(lambda v: v.get("picker", {}).get("count") == 0, "Zero-match filtering failed")
        send("\x7f" * 4)  # Clear query through Backspace in either key configuration.
        snapshot(ready, "Clearing the filter did not restore the native frame")
        send("\x03")  # C-c
        closed = snapshot(lambda v: not v.get("picker") and v["origin"], "Closing did not restore source focus")
        assert closed["native_buffers"] == 0
        send(" su")  # actual configured undo mapping
        if configured:
            drain(6)  # Let unrelated toolchain startup notifications expire.
        snapshot(lambda v: v.get("picker", {}).get("focus"), "Undo picker did not open")
        send("\x1b[A" if configured else "\x1b[B")
        undo = snapshot(ready, "Undo mapping did not use the native backend")
        assert "local value" in undo["picker"]["screen"], json.dumps(undo["picker"], ensure_ascii=False)
        send("\x1bz")  # Alt+Z from undo input in Insert mode
        wrapped = snapshot(lambda v: ready(v) and v["picker"]["wrap"], "Undo Alt+Z did not enable wrapping")
        assert wrapped["picker"]["window_wrap"] and wrapped["picker"]["query"] == ""
        send("\x1bOS")  # F4: compare with current snapshot
        snapshot(lambda v: ready(v) and v["picker"].get("compare") == "current" and v["picker"]["wrap"], "F4 lost undo wrapping")
        send("\x1bz")
        snapshot(lambda v: ready(v) and not v["picker"]["wrap"], "Undo Alt+Z did not disable wrapping")
        send("\x1bOS")
        snapshot(lambda v: ready(v) and v["picker"].get("compare") == "parent", "Undo parent comparison did not return")
        send("#0")  # Root has a snapshot rather than a diff renderer.
        snapshot(lambda v: v.get("picker", {}).get("lines") == ["Initial state (no parent change)"], "Initial undo snapshot did not appear")
        send("\x1bz")
        snapshot(lambda v: v.get("picker", {}).get("window_wrap") and v["picker"]["focus"] and v["mode"] == "i", "Alt+Z did not work on the initial snapshot")
        send("\x1bOS")
        snapshot(lambda v: ready(v) and v["picker"].get("compare") == "current" and v["picker"]["wrap"], "Snapshot-to-diff switch lost wrap")
        send("\x03")
        snapshot(lambda v: not v.get("picker") and v["origin"] and v["native_buffers"] == 0, "Undo close leaked a frame")
        assert len(transcript) > 500
        print("Native diff TUI" + (" (" + layout + ")" if layout != "unified" else "") + (" (configured)" if configured else "") + ": visible gutters/code, live themes, rapid switching, resize, filters, undo and cleanup passed")
    finally:
        send("\x1b:qa!\r")
        try:
            child.wait(timeout=3)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()
        os.close(master)
        os.close(slave)
