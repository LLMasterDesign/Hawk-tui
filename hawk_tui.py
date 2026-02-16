#!/usr/bin/env python3
"""Hawk-tui: generic operator TUI with awk-powered command library.

5-box layout:
1) Left nav (full height)
2) Main top
3) Main bottom
4) Right ops (detail + live log split)
5) Right chat/details (full height)
"""

import argparse
import curses
import json
import os
import subprocess
import textwrap
import time
from collections import deque
from datetime import datetime
from pathlib import Path

NAV_ITEMS = ["Overview", "gRPC", "Streams", "Commands"]
MOTION = ["|", "/", "-", "-", "-", "-", "\\", "|"]
MOTION_FPS = 6
HEADER = "▛▞//"

CP_DEFAULT = 1
CP_ORANGE = 2
CP_BANNER = 3
CP_DIM = 4
CP_GOOD = 5
CP_WARN = 6
CP_MUTED = 7


class HawkConfig:
    def __init__(self, base_dir: Path):
        self.base_dir = base_dir
        self.bin = base_dir / "bin" / "hawk-cmd"
        self.adapters = base_dir / "adapters"

        self.log_file = Path(os.environ.get("HAWK_LOG_FILE", str(base_dir / "shell" / "fake_env" / "runtime.log")))
        self.stream_file = Path(os.environ.get("HAWK_STREAM_FILE", str(base_dir / "shell" / "fake_env" / "stream.events")))
        self.grpc_targets = Path(os.environ.get("HAWK_GRPC_TARGETS", str(base_dir / "shell" / "fake_env" / "grpc.targets")))
        self.grpc_fake = Path(os.environ.get("HAWK_GRPC_FAKE_FILE", str(base_dir / "shell" / "fake_env" / "grpc_health.jsonl")))
        self.units_file = Path(os.environ.get("HAWK_UNITS_FILE", str(base_dir / "conf" / "systemd_units.txt")))
        self.chat_file = Path(os.environ.get("HAWK_CHAT_FILE", str(base_dir / "agent_chat.log")))
        self.default_unit = os.environ.get("HAWK_DAEMON_UNIT", "hawk-agent.service")


class StateCache:
    def __init__(self):
        self.command_catalog = []
        self.selected_command = 0

        self.grpc_rows = []
        self.grpc_last = "never"
        self.grpc_ok = 0
        self.grpc_bad = 0

        self.stream_rows = []
        self.stream_last = "never"

        self.command_output = []
        self.command_last = "never"

        self.log_tail = []
        self.log_size = 0
        self.log_delta = 0
        self.log_last = "never"

        self.chat_tail = []
        self.control_tail = deque(maxlen=400)

        self._last_grpc_poll = 0.0
        self._last_stream_poll = 0.0
        self._last_cmd_poll = 0.0
        self._last_log_poll = 0.0
        self._last_chat_poll = 0.0

    def ctl(self, line: str):
        stamp = datetime.now().strftime("%H:%M:%S")
        self.control_tail.append(f"{stamp} {line}")


# ▛▞// utilities :: hawk.tui.util
# @ctx ⫸ [shell.wrap.render]

def run_capture(cmd, cwd=None, timeout=4):
    try:
        res = subprocess.run(
            cmd,
            cwd=cwd,
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
        out = (res.stdout or "") + (res.stderr or "")
        return res.returncode, out.strip()
    except Exception as exc:
        return 1, str(exc)


def safe_add(win, y, x, text, attr=0):
    try:
        h, w = win.getmaxyx()
        if y < 0 or y >= h or x >= w:
            return
        max_len = max(0, w - x - 1)
        if max_len <= 0:
            return
        win.addnstr(y, x, text, max_len, attr)
    except curses.error:
        pass


def wrap_lines(text, width):
    if width <= 1:
        return [text[: max(0, width)]]
    parts = textwrap.wrap(
        text,
        width=width,
        replace_whitespace=False,
        drop_whitespace=False,
        break_long_words=True,
        break_on_hyphens=False,
    )
    return parts or [""]


def safe_add_wrapped(win, y, x, text, width, attr=0, max_lines=None):
    lines = wrap_lines(text, width)
    if max_lines is not None:
        lines = lines[:max_lines]
    for i, line in enumerate(lines):
        safe_add(win, y + i, x, line, attr)
    return len(lines)


def tail_lines(path: Path, n=120):
    if not path.exists():
        return []
    q = deque(maxlen=n)
    with path.open("r", encoding="utf-8", errors="replace") as f:
        for line in f:
            q.append(line.rstrip("\n"))
    return list(q)


def init_colors():
    if not curses.has_colors():
        return
    curses.start_color()
    curses.use_default_colors()

    orange = curses.COLOR_YELLOW
    muted = curses.COLOR_CYAN
    if curses.COLORS >= 256:
        orange = 208
        muted = 245

    curses.init_pair(CP_DEFAULT, -1, -1)
    curses.init_pair(CP_ORANGE, orange, -1)
    curses.init_pair(CP_BANNER, curses.COLOR_BLACK, orange)
    curses.init_pair(CP_DIM, curses.COLOR_CYAN, -1)
    curses.init_pair(CP_GOOD, curses.COLOR_GREEN, -1)
    curses.init_pair(CP_WARN, curses.COLOR_RED, -1)
    curses.init_pair(CP_MUTED, muted, -1)


def pane_title(win, title, accent=False):
    win.erase()
    attr = curses.A_BOLD
    if accent:
        attr |= curses.color_pair(CP_ORANGE)
    win.box()
    safe_add(win, 0, 2, f" {HEADER} {title} ", attr)


# :: ∎

# ▛▞// data polling :: hawk.tui.poll
# @ctx ⫸ [catalog.grpc.chat]

def poll_catalog(cfg: HawkConfig, cache: StateCache):
    code, out = run_capture([str(cfg.bin), "list"], cwd=str(cfg.base_dir))
    rows = []
    if code == 0 and out:
        for line in out.splitlines():
            parts = [p.strip() for p in line.split("|", 3)]
            if len(parts) == 4:
                rows.append(
                    {
                        "id": parts[0],
                        "title": parts[1],
                        "runner": parts[2],
                        "desc": parts[3],
                    }
                )
    cache.command_catalog = rows
    if cache.selected_command >= len(rows):
        cache.selected_command = 0


def poll_grpc(cfg: HawkConfig, cache: StateCache):
    code, out = run_capture([str(cfg.bin), "run", "grpc_health"], cwd=str(cfg.base_dir), timeout=6)
    rows = []
    ok = 0
    bad = 0

    if code == 0 and out:
        for line in out.splitlines():
            # expected: endpoint\tstatus\tlatency_ms\tsource
            parts = line.split("\t")
            if len(parts) < 4:
                continue
            status = parts[1].strip().upper()
            if status == "SERVING":
                ok += 1
            else:
                bad += 1
            rows.append(
                {
                    "endpoint": parts[0].strip(),
                    "status": status,
                    "latency": parts[2].strip(),
                    "source": parts[3].strip(),
                }
            )

    cache.grpc_rows = rows
    cache.grpc_ok = ok
    cache.grpc_bad = bad
    cache.grpc_last = datetime.now().strftime("%H:%M:%S")


def poll_streams(cfg: HawkConfig, cache: StateCache):
    code, out = run_capture([str(cfg.bin), "run", "stream_lag"], cwd=str(cfg.base_dir), timeout=5)
    rows = []
    if code == 0 and out:
        for line in out.splitlines():
            rows.append(line)
    cache.stream_rows = rows
    cache.stream_last = datetime.now().strftime("%H:%M:%S")


def poll_command(cfg: HawkConfig, cache: StateCache):
    if not cache.command_catalog:
        cache.command_output = ["no commands loaded"]
        return

    cmd_id = cache.command_catalog[cache.selected_command]["id"]
    code, out = run_capture([str(cfg.bin), "run", cmd_id], cwd=str(cfg.base_dir), timeout=6)
    if code == 0 and out:
        cache.command_output = out.splitlines()[-80:]
    elif code == 0:
        cache.command_output = ["(no output)"]
    else:
        cache.command_output = [f"command failed: {cmd_id}", out or "unknown error"]
    cache.command_last = datetime.now().strftime("%H:%M:%S")


def poll_logs_and_chat(cfg: HawkConfig, cache: StateCache):
    if cfg.log_file.exists():
        sz = cfg.log_file.stat().st_size
        cache.log_delta = max(0, sz - cache.log_size)
        cache.log_size = sz
        cache.log_last = datetime.fromtimestamp(cfg.log_file.stat().st_mtime).strftime("%H:%M:%S")
    cache.log_tail = tail_lines(cfg.log_file, 200)

    cfg.chat_file.parent.mkdir(parents=True, exist_ok=True)
    if not cfg.chat_file.exists():
        cfg.chat_file.write_text("", encoding="utf-8")
    cache.chat_tail = tail_lines(cfg.chat_file, 200)


def periodic_poll(cfg: HawkConfig, cache: StateCache):
    now = time.time()

    if now - cache._last_grpc_poll >= 2.0:
        poll_grpc(cfg, cache)
        cache._last_grpc_poll = now

    if now - cache._last_stream_poll >= 2.0:
        poll_streams(cfg, cache)
        cache._last_stream_poll = now

    if now - cache._last_cmd_poll >= 2.5:
        poll_command(cfg, cache)
        cache._last_cmd_poll = now

    if now - cache._last_log_poll >= 0.8:
        poll_logs_and_chat(cfg, cache)
        cache._last_log_poll = now


# :: ∎

# ▛▞// controls :: hawk.tui.controls
# @ctx ⫸ [daemon.actions.prompt]

def append_chat(chat_file: Path, text: str):
    if not text.strip():
        return
    stamp = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    with chat_file.open("a", encoding="utf-8") as f:
        f.write(f"{stamp} {text.strip()}\n")


def daemon_action(cfg: HawkConfig, cache: StateCache, action: str):
    cmd = [str(cfg.base_dir / "adapters" / "daemon_ctl.sh"), action, cfg.default_unit]
    code, out = run_capture(cmd, cwd=str(cfg.base_dir), timeout=6)
    if code == 0:
        cache.ctl(f"{action} ok :: {cfg.default_unit}")
        if out:
            for line in out.splitlines()[-6:]:
                cache.ctl(line)
    else:
        cache.ctl(f"{action} failed :: {cfg.default_unit}")
        if out:
            for line in out.splitlines()[-6:]:
                cache.ctl(line)


def prompt(stdscr, text):
    h, w = stdscr.getmaxyx()
    stdscr.nodelay(False)
    curses.echo()
    curses.curs_set(1)

    safe_add(stdscr, h - 1, 0, " " * (w - 1), curses.color_pair(CP_BANNER))
    safe_add(stdscr, h - 1, 0, text, curses.A_BOLD | curses.color_pair(CP_BANNER))
    stdscr.refresh()

    max_len = max(1, w - len(text) - 1)
    raw = stdscr.getstr(h - 1, len(text), max_len)
    val = raw.decode("utf-8", errors="replace").strip()

    curses.noecho()
    curses.curs_set(0)
    stdscr.nodelay(True)
    return val


# :: ∎

# ▛▞// drawing :: hawk.tui.draw
# ⫸ [nav.main.layout]

def draw_banner(stdscr, frame):
    h, w = stdscr.getmaxyx()
    now = datetime.now().strftime("%H:%M:%S")
    text = f" Hawk-tui [{frame}] {now} "
    fill = "█" * max(0, w - len(text) - 1)
    safe_add(stdscr, 0, 0, "".ljust(w), curses.color_pair(CP_BANNER))
    safe_add(stdscr, 0, 1, text + fill, curses.A_BOLD | curses.color_pair(CP_BANNER))


def draw_left_nav(win, selected, flash):
    h, w = win.getmaxyx()
    pane_title(win, "NAV", accent=True)

    safe_add(win, 1, 2, "████████████████████████████", curses.color_pair(CP_ORANGE))
    safe_add(win, 2, 2, "▛▞// Hawk-tui", curses.A_BOLD | curses.color_pair(CP_ORANGE))
    safe_add_wrapped(
        win,
        3,
        2,
        "awk-command operator surface",
        max(8, w - 4),
        curses.color_pair(CP_MUTED),
        max_lines=2,
    )

    nav_cards = [
        ("🛰", "OVERVIEW", ["runtime snapshot", "buffer growth and ingest"]),
        ("🩺", "GRPC", ["serving vs non-serving", "latency per endpoint"]),
        ("🌊", "STREAMS", ["lag by stream", "moving event activity"]),
        ("🧰", "COMMANDS", ["awk command palette", "run selected command"]),
    ]

    inner_w = max(10, w - 4)
    frame_w = max(8, inner_w - 2)
    row = 5
    reserve_for_controls = 10

    for i, (emoji, label, subs) in enumerate(nav_cards):
        if row + 3 >= h - reserve_for_controls:
            break

        is_selected = i == selected
        title_attr = curses.A_BOLD | (curses.color_pair(CP_ORANGE) if is_selected else curses.color_pair(CP_MUTED))
        frame_attr = curses.color_pair(CP_ORANGE) if is_selected else curses.color_pair(CP_DIM)
        marker = "▾" if is_selected else "▸"
        title = f" {i+1} {HEADER} {emoji} {label} {marker} "

        safe_add(win, row, 2, f"┌{'─' * frame_w}┐", frame_attr)
        safe_add(win, row + 1, 2, f"│{title.ljust(frame_w)[:frame_w]}│", title_attr)
        safe_add(win, row + 2, 2, f"└{'─' * frame_w}┘", frame_attr)
        row += 3

        if is_selected and row + 2 < h - reserve_for_controls:
            for sub in subs:
                if row >= h - reserve_for_controls:
                    break
                safe_add_wrapped(
                    win,
                    row,
                    4,
                    f"• {sub}",
                    max(6, w - 8),
                    curses.color_pair(CP_MUTED),
                    max_lines=1,
                )
                row += 1
        row += 1

    k = max(row, h - 9)
    safe_add(win, k, 2, "Controls", curses.A_BOLD | curses.color_pair(CP_ORANGE))
    keys = [
        "a/z/e daemon",
        "h/u health status",
        "[ ] choose command",
        "enter run command",
        "m add note",
        "r refresh   q quit",
    ]
    for i, line in enumerate(keys):
        if k + 1 + i >= h - 2:
            break
        safe_add(win, k + 1 + i, 2, f"- {line}", curses.A_DIM)

    if flash:
        safe_add_wrapped(
            win,
            h - 2,
            2,
            flash,
            max(8, w - 4),
            curses.A_BOLD | curses.color_pair(CP_ORANGE),
            max_lines=1,
        )


def draw_main_overview(top, bottom, cfg: HawkConfig, cache: StateCache):
    pane_title(top, "MAIN TOP :: OVERVIEW", accent=True)
    pane_title(bottom, "MAIN BOTTOM :: RATE WINDOW", accent=True)

    lines = [
        f"log file        : {cfg.log_file}",
        f"stream file     : {cfg.stream_file}",
        f"grpc targets    : {cfg.grpc_targets}",
        f"grpc checks     : ok={cache.grpc_ok} bad={cache.grpc_bad} last={cache.grpc_last}",
        f"log bytes       : {cache.log_size}",
        f"log growth      : +{cache.log_delta} bytes",
        f"command poll    : {cache.command_last}",
    ]
    for i, line in enumerate(lines):
        safe_add(top, i + 1, 2, line)

    for i, line in enumerate(cache.stream_rows[:10]):
        safe_add(bottom, i + 1, 2, line)


def draw_main_grpc(top, bottom, cache: StateCache):
    pane_title(top, "MAIN TOP :: GRPC HEALTH", accent=True)
    pane_title(bottom, "MAIN BOTTOM :: ENDPOINT TABLE", accent=True)

    safe_add(top, 1, 2, f"last poll: {cache.grpc_last}")
    safe_add(top, 2, 2, f"serving: {cache.grpc_ok}", curses.A_BOLD | curses.color_pair(CP_GOOD))
    safe_add(top, 3, 2, f"non-serving: {cache.grpc_bad}", curses.A_BOLD | curses.color_pair(CP_WARN))

    for i, row in enumerate(cache.grpc_rows[:16]):
        attr = curses.color_pair(CP_GOOD) if row["status"] == "SERVING" else curses.color_pair(CP_WARN)
        safe_add(bottom, i + 1, 2, f"{row['endpoint']:<32} {row['status']:<12} {row['latency']:<8} {row['source']}", attr)


def draw_main_streams(top, bottom, cache: StateCache):
    pane_title(top, "MAIN TOP :: STREAM LAG", accent=True)
    pane_title(bottom, "MAIN BOTTOM :: STREAM SUMMARY", accent=True)

    safe_add(top, 1, 2, f"last poll: {cache.stream_last}")
    rows = cache.stream_rows[: max(1, top.getmaxyx()[0] - 3)]
    for i, line in enumerate(rows):
        safe_add(top, i + 2, 2, line)

    recent = cache.log_tail[-12:]
    for i, line in enumerate(recent):
        safe_add(bottom, i + 1, 2, line)


def draw_main_commands(top, bottom, cache: StateCache):
    pane_title(top, "MAIN TOP :: COMMAND LIBRARY", accent=True)
    pane_title(bottom, "MAIN BOTTOM :: SELECTED OUTPUT", accent=True)

    if not cache.command_catalog:
        safe_add(top, 1, 2, "No command catalog loaded.")
        return

    row = 1
    for i, cmd in enumerate(cache.command_catalog[:12]):
        attr = curses.A_BOLD if i == cache.selected_command else curses.A_NORMAL
        if i == cache.selected_command:
            attr |= curses.A_REVERSE | curses.color_pair(CP_ORANGE)
        safe_add(top, row, 2, f"{cmd['id']:<16} {cmd['title']}", attr)
        row += 1

    safe_add(top, row + 1, 2, f"last run: {cache.command_last}")

    for i, line in enumerate(cache.command_output[: max(1, bottom.getmaxyx()[0] - 2)]):
        safe_add(bottom, i + 1, 2, line)


def draw_main(main_win, selected, cfg, cache):
    pane_title(main_win, f"MAIN :: {NAV_ITEMS[selected].upper()}", accent=True)
    h, w = main_win.getmaxyx()
    inner_h = h - 2
    split_gap = 1
    top_h = max(3, (inner_h - split_gap) // 2)
    bot_h = max(3, inner_h - top_h - split_gap)

    top = main_win.derwin(top_h, w - 2, 1, 1)
    bottom = main_win.derwin(bot_h, w - 2, 1 + top_h + split_gap, 1)

    if selected == 0:
        draw_main_overview(top, bottom, cfg, cache)
    elif selected == 1:
        draw_main_grpc(top, bottom, cache)
    elif selected == 2:
        draw_main_streams(top, bottom, cache)
    else:
        draw_main_commands(top, bottom, cache)


def draw_ops(win, cache, frame):
    pane_title(win, "OPS :: DETAIL + LIVE LOG", accent=True)
    h, w = win.getmaxyx()
    inner_h = h - 2
    split_gap = 1
    top_h = max(5, (inner_h - split_gap) // 2)
    bot_h = max(5, inner_h - top_h - split_gap)

    d = win.derwin(top_h, w - 2, 1, 1)
    l = win.derwin(bot_h, w - 2, 1 + top_h + split_gap, 1)
    d.erase()
    l.erase()

    safe_add(win, 1 + top_h, 1, "·" * max(0, w - 2), curses.color_pair(CP_DIM))

    safe_add(d, 0, 0, "Control plane", curses.A_BOLD | curses.color_pair(CP_ORANGE))
    ctl = list(cache.control_tail)[-max(1, top_h - 2):]
    for i, line in enumerate(ctl):
        safe_add(d, i + 1, 0, line)

    safe_add(l, 0, 0, f"Run log [{frame}]", curses.A_BOLD | curses.color_pair(CP_ORANGE))
    tail = cache.log_tail[-max(1, bot_h - 2):]
    for i, line in enumerate(tail):
        safe_add(l, i + 1, 0, line, curses.A_DIM)


def draw_chat(win, cache):
    pane_title(win, "CHAT :: DETAILS", accent=True)
    h, w = win.getmaxyx()

    safe_add(win, 1, 2, "Agent notes", curses.A_BOLD | curses.color_pair(CP_ORANGE))
    safe_add(win, 2, 2, f"log bytes={cache.log_size} delta={cache.log_delta}", curses.color_pair(CP_MUTED))

    wrapped = []
    for raw in cache.chat_tail[-80:]:
        wrapped.extend(wrap_lines(raw, max(8, w - 4)))

    lines = wrapped[-max(1, h - 5):]
    if not wrapped:
        safe_add(win, 4, 2, "No notes yet. Press m to append.", curses.color_pair(CP_MUTED))
        return

    row = 4
    for line in lines:
        safe_add(win, row, 2, line)
        row += 1
        if row >= h - 1:
            break


def draw_all(stdscr, selected, cfg, cache, flash, frame):
    stdscr.erase()
    h, w = stdscr.getmaxyx()

    if h < 28 or w < 150:
        safe_add(stdscr, 1, 2, "Terminal too small for Hawk-tui.", curses.A_BOLD)
        safe_add(stdscr, 2, 2, f"Current {w}x{h}; need at least 150x28")
        safe_add(stdscr, 4, 2, "Resize then press r. q to quit.")
        stdscr.refresh()
        return

    draw_banner(stdscr, frame)

    body_h = h - 1
    nav_w = 30
    chat_w = 30
    gutter = 1
    core_w = w - nav_w - chat_w - (3 * gutter)
    main_w = max(52, (core_w * 2) // 3)
    ops_w = core_w - main_w
    if ops_w < 28:
        main_w -= max(0, 28 - ops_w)
        ops_w = core_w - main_w

    left = stdscr.derwin(body_h, nav_w, 1, 0)
    main_x = nav_w + gutter
    ops_x = main_x + main_w + gutter
    chat_x = ops_x + ops_w + gutter
    main = stdscr.derwin(body_h, main_w, 1, main_x)
    ops = stdscr.derwin(body_h, ops_w, 1, ops_x)
    chat = stdscr.derwin(body_h, chat_w, 1, chat_x)

    draw_left_nav(left, selected, flash)
    draw_main(main, selected, cfg, cache)
    draw_ops(ops, cache, frame)
    draw_chat(chat, cache)

    stdscr.refresh()


# :: ∎

# ▛▞// runtime :: hawk.tui.run
# ⫸ [check.loop.dispatch]

def run_check(cfg, cache):
    poll_catalog(cfg, cache)
    poll_grpc(cfg, cache)
    poll_streams(cfg, cache)
    poll_command(cfg, cache)
    poll_logs_and_chat(cfg, cache)

    data = {
        "app": "hawk-tui",
        "commands": len(cache.command_catalog),
        "grpc_ok": cache.grpc_ok,
        "grpc_bad": cache.grpc_bad,
        "stream_rows": len(cache.stream_rows),
        "log_size": cache.log_size,
        "log_delta": cache.log_delta,
    }
    print(json.dumps(data, indent=2))


def run_ui(stdscr, cfg: HawkConfig):
    curses.curs_set(0)
    stdscr.nodelay(True)
    init_colors()

    cache = StateCache()
    poll_catalog(cfg, cache)
    periodic_poll(cfg, cache)

    selected = 0
    flash = ""
    flash_until = 0.0

    while True:
        now = time.time()
        frame = MOTION[int(now * MOTION_FPS) % len(MOTION)]

        periodic_poll(cfg, cache)

        if flash_until and now > flash_until:
            flash = ""
            flash_until = 0.0

        draw_all(stdscr, selected, cfg, cache, flash, frame)

        key = stdscr.getch()
        if key == -1:
            time.sleep(0.04)
            continue

        if key in (ord("q"), ord("Q")):
            break
        elif key in (curses.KEY_UP, ord("k")):
            selected = (selected - 1) % len(NAV_ITEMS)
        elif key in (curses.KEY_DOWN, ord("j")):
            selected = (selected + 1) % len(NAV_ITEMS)
        elif key in (ord("1"), ord("2"), ord("3"), ord("4")):
            selected = int(chr(key)) - 1
        elif key == ord("["):
            if cache.command_catalog:
                cache.selected_command = (cache.selected_command - 1) % len(cache.command_catalog)
                flash = f"selected cmd: {cache.command_catalog[cache.selected_command]['id']}"
                flash_until = time.time() + 1.5
        elif key == ord("]"):
            if cache.command_catalog:
                cache.selected_command = (cache.selected_command + 1) % len(cache.command_catalog)
                flash = f"selected cmd: {cache.command_catalog[cache.selected_command]['id']}"
                flash_until = time.time() + 1.5
        elif key in (10, 13):
            poll_command(cfg, cache)
            flash = "command executed"
            flash_until = time.time() + 1.5
        elif key in (ord("r"), ord("R")):
            poll_catalog(cfg, cache)
            poll_grpc(cfg, cache)
            poll_streams(cfg, cache)
            poll_command(cfg, cache)
            poll_logs_and_chat(cfg, cache)
            flash = "refreshed"
            flash_until = time.time() + 1.5
        elif key in (ord("a"), ord("A")):
            daemon_action(cfg, cache, "start")
        elif key in (ord("z"), ord("Z")):
            daemon_action(cfg, cache, "stop")
        elif key in (ord("e"), ord("E")):
            daemon_action(cfg, cache, "restart")
        elif key in (ord("h"), ord("H")):
            daemon_action(cfg, cache, "health")
        elif key in (ord("u"), ord("U")):
            daemon_action(cfg, cache, "status")
        elif key in (ord("m"), ord("M")):
            msg = prompt(stdscr, "Note> ")
            if msg:
                append_chat(cfg.chat_file, msg)
                poll_logs_and_chat(cfg, cache)
                flash = "note appended"
            else:
                flash = "empty note"
            flash_until = time.time() + 1.8


def main():
    parser = argparse.ArgumentParser(description="Hawk-tui")
    parser.add_argument("--check", action="store_true", help="poll data once and print JSON")
    args = parser.parse_args()

    base = Path(__file__).resolve().parent
    cfg = HawkConfig(base)
    cache = StateCache()

    if args.check:
        run_check(cfg, cache)
        return

    curses.wrapper(run_ui, cfg)


if __name__ == "__main__":
    main()

# :: ∎
