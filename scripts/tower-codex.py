#!/usr/bin/env python3
"""Capture Codex lifecycle metadata and serve one local Watchtower board."""

import argparse
from contextlib import closing
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import sqlite3
import subprocess
import sys
import tempfile
import time
from urllib.parse import urlsplit


SCRIPT = Path(__file__).resolve()
ASSETS = SCRIPT.parents[1] / "assets"
EVENTS = {
    "UserPromptSubmit": "working",
    "PreModelRequest": "working",
    "SubagentStart": "working",
    "SubagentStop": "idle",
    "Stop": "idle",
    "Interrupt": "interrupted",
    "SessionEnd": "closed",
}
SCHEMA = """
CREATE TABLE IF NOT EXISTS activity (
    actor TEXT PRIMARY KEY, kind TEXT NOT NULL, role TEXT NOT NULL,
    worktree TEXT NOT NULL, model TEXT NOT NULL, turn TEXT NOT NULL,
    state TEXT NOT NULL, updated INTEGER NOT NULL, bound_worktree TEXT NOT NULL DEFAULT ''
)
"""
# A process can disappear without a stop event. Keep old records for diagnosis,
# but stop claiming they are working after a quiet period.
STALE_AFTER = 10 * 60
KEEP_FOR = 24 * 60 * 60


def git_path(cwd, argument):
    return Path(subprocess.check_output(
        ["git", "-C", str(cwd), "rev-parse", "--path-format=absolute", argument],
        stderr=subprocess.DEVNULL, text=True, timeout=1,
    ).strip())


def database_path(cwd):
    state = os.environ.get("TOWER_HOME")
    home = (Path(cwd) / state) if state else git_path(cwd, "--git-common-dir") / "watchtower"
    return home / "codex.sqlite3"


def identifier(value):
    return value if isinstance(value, str) and re.fullmatch(r"[a-zA-Z0-9_.:-]{1,160}", value) else ""


def record(event):
    state = EVENTS.get(event.get("hook_event_name"))
    session = identifier(event.get("session_id"))
    agent = identifier(event.get("agent_id"))
    cwd = event.get("cwd")
    if not state or not session or not isinstance(cwd, str):
        return
    path = database_path(cwd)
    if not path.is_file():
        return
    # Use only the hook's reported working directory. Codex can run subagents
    # in the parent's directory and send individual shell calls to worktrees.
    worktree = git_path(cwd, "--show-toplevel").name
    turn = identifier(event.get("turn_id"))
    now = int(time.time())
    # mode=rw avoids silently recreating a database after tracking is disabled.
    with closing(sqlite3.connect(path.resolve().as_uri() + "?mode=rw", uri=True, timeout=1)) as db, db:
        db.execute(
            """INSERT INTO activity (actor, kind, role, worktree, model, turn, state, updated)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)
               ON CONFLICT(actor) DO UPDATE SET
                 kind = CASE WHEN excluded.kind = 'agent' THEN 'agent' ELSE kind END,
                 role = COALESCE(NULLIF(excluded.role, ''), role),
                 worktree = excluded.worktree,
                 model = COALESCE(NULLIF(excluded.model, ''), model),
                 turn = COALESCE(NULLIF(excluded.turn, ''), turn),
                 state = excluded.state, updated = excluded.updated
               WHERE excluded.state = 'working' OR excluded.turn IN ('', turn) OR turn = ''""",
            (agent or session, "agent" if agent else "session",
             identifier(event.get("agent_type")), worktree, identifier(event.get("model")),
             turn, state, now),
        )
        db.execute("DELETE FROM activity WHERE updated < ?", (now - KEEP_FOR,))


def capture():
    # All handlers are observational. An unavailable project or a locked DB
    # must never block Codex, and these hooks must emit valid JSON for Stop.
    try:
        event = json.load(sys.stdin)
        if isinstance(event, dict):
            record(event)
    except (TypeError, ValueError, OSError, sqlite3.Error, subprocess.SubprocessError):
        pass
    print("{}")


def bind_worktree():
    # A worker's first tower-area step runs from the assigned worktree. The
    # command environment identifies the actual Codex actor, without role guesses.
    actor = identifier(os.getenv("CODEX_THREAD_ID"))
    if actor:
        cwd = Path.cwd()
        path = database_path(cwd)
        with closing(sqlite3.connect(path.resolve().as_uri() + "?mode=rw", uri=True, timeout=1)) as db, db:
            db.execute("UPDATE activity SET bound_worktree = ? WHERE actor = ?",
                       (git_path(cwd, "--show-toplevel").name, actor))


def install_hooks(config_path):
    command = shlex.join([sys.executable, str(SCRIPT), "hook"])
    original = config_path.read_bytes() if config_path.exists() else None
    config = json.loads(original) if original is not None else {}
    if not isinstance(config, dict):
        raise ValueError("Existing Codex hook configuration must be a JSON object")
    hooks = config.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise ValueError("Existing Codex hooks must be a JSON object")
    for event in EVENTS:
        groups = hooks.setdefault(event, [])
        if not isinstance(groups, list):
            raise ValueError(f"Existing {event} hooks must be a list")
        handlers = [handler for group in groups for handler in group.get("hooks", [])]
        if any(handler.get("command") == command for handler in handlers):
            continue
        # Preserve unrelated hooks. Refuse a second active Watchtower path.
        if any("tower-codex.py" in handler.get("command", "") for handler in handlers):
            raise ValueError(f"{event} already has a Watchtower hook from another checkout")
        groups.append({"hooks": [{"type": "command", "command": command, "timeout": 3}]})
    config_path.parent.mkdir(parents=True, exist_ok=True)
    encoded = (json.dumps(config, indent=2, ensure_ascii=False) + "\n").encode()
    if original == encoded:
        return
    with tempfile.NamedTemporaryFile(dir=config_path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(encoded)
            stream.close()
            if (config_path.read_bytes() if config_path.exists() else None) != original:
                raise ValueError("Codex hooks changed during setup. Retry with the latest file.")
            if config_path.exists():
                temporary.chmod(config_path.stat().st_mode & 0o777)
            temporary.replace(config_path)
        finally:
            temporary.unlink(missing_ok=True)


def snapshot(path):
    now = int(time.time())
    with closing(sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True, timeout=1)) as db:
        db.row_factory = sqlite3.Row
        rows = db.execute(
            """SELECT actor, kind, role, COALESCE(NULLIF(bound_worktree, ''), worktree) AS worktree, model,
                      CASE WHEN state = 'working' AND updated < ? THEN 'stale' ELSE state END AS state,
                      updated
               FROM activity WHERE updated >= ?
               ORDER BY (state = 'working' AND updated >= ?) DESC, updated DESC LIMIT 100""",
            (now - STALE_AFTER, now - KEEP_FOR, now - STALE_AFTER),
        ).fetchall()
    return [dict(row) for row in rows]


def serve(port):
    cwd = Path.cwd()
    git_path(cwd, "--show-toplevel")
    path = database_path(cwd)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.touch(mode=0o600)
    with closing(sqlite3.connect(path)) as db, db:
        db.execute(SCHEMA)
    prefix = "/" + secrets.token_urlsafe(24) + "/"
    html = (ASSETS / "board.html").read_bytes().replace(
        b'<main id="board">', b'<main id="board" data-codex>', 1,
    )
    assets = {
        "": ("text/html; charset=utf-8", html),
        "avatars.css": ("text/css; charset=utf-8", (ASSETS / "avatars.css").read_bytes()),
        "avatars.js": ("text/javascript; charset=utf-8", b"window.__avatars=" + (ASSETS / "avatars.json").read_bytes()),
    }

    class BoardHandler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            route = urlsplit(self.path).path
            if self.headers.get("Host") != f"127.0.0.1:{self.server.server_port}" or not route.startswith(prefix):
                self.send_error(404)
                return
            name = route[len(prefix):]
            try:
                if name == "fleet.json":
                    result = subprocess.check_output(
                        [str(SCRIPT.with_name("tower-board.sh")), "--json"], cwd=cwd, timeout=10,
                        env={**os.environ, "TOWER_NO_CI": "1"}, stderr=subprocess.DEVNULL,
                    )
                    fleet = json.loads(result)
                    fleet["codex"] = snapshot(path)
                    content_type, body = "application/json", json.dumps(fleet).encode()
                elif name in assets:
                    content_type, body = assets[name]
                else:
                    self.send_error(404)
                    return
            except (OSError, ValueError, sqlite3.Error, subprocess.SubprocessError):
                self.send_error(503, "Watchtower state is temporarily unavailable")
                return
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Security-Policy",
                             "default-src 'self'; script-src 'self' 'unsafe-inline'; "
                             "style-src 'self' 'unsafe-inline'; frame-ancestors 'none'")
            self.end_headers()
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass

    with ThreadingHTTPServer(("127.0.0.1", port), BoardHandler) as server:
        print(f"http://127.0.0.1:{server.server_port}{prefix}", flush=True)
        server.serve_forever()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("hook")
    commands.add_parser("bind")
    setup = commands.add_parser("install", help="Register observational hooks for local Codex")
    setup.add_argument("--config", type=Path,
                       default=Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")) / "hooks.json")
    board = commands.add_parser("board", help="Serve the live board for this repository")
    board.add_argument("--port", type=int, default=0)
    args = parser.parse_args()
    try:
        if args.command == "hook":
            capture()
        elif args.command == "bind":
            bind_worktree()
        elif args.command == "install":
            install_hooks(args.config.expanduser().resolve())
            print("Review the Watchtower hooks in Codex Settings > Hooks (CLI: /hooks).")
        else:
            serve(args.port)
    except KeyboardInterrupt:
        return
    except (OSError, ValueError, AttributeError, TypeError, sqlite3.Error, subprocess.SubprocessError) as error:
        parser.exit(1, f"watchtower: {error}\n")


if __name__ == "__main__":
    main()
