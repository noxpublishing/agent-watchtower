"""Regressions for the Codex lifecycle, project scope and board transport."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import urllib.error
import urllib.request


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
COMMAND = [sys.executable, str(SCRIPTS / "tower-codex.py")]


class CodexBoard(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="tower-codex-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.repo = self.root / "repo"
        self.env = {key: value for key, value in os.environ.items() if key != "TOWER_HOME"}
        self.run_command(["git", "init", "-q", "-b", "main", str(self.repo)], cwd=self.root)
        self.run_command(["git", "-c", "user.name=Test", "-c", "user.email=t@example.invalid",
                          "commit", "-q", "--allow-empty", "-m", "Fixture"])

    def run_command(self, args, cwd=None, stdin=None, env=None):
        return subprocess.run(args, cwd=cwd or self.repo, env=env or self.env, input=stdin,
                              capture_output=True, text=True, check=True, timeout=15).stdout

    def hook(self, event, **fields):
        payload = {"hook_event_name": event, "cwd": str(self.repo),
                   "session_id": "root", "turn_id": "turn-1", **fields}
        self.assertEqual(json.loads(self.run_command([*COMMAND, "hook"], stdin=json.dumps(payload))), {})

    def start_board(self):
        process = subprocess.Popen([*COMMAND, "board"], cwd=self.repo, env=self.env,
                                   stdout=subprocess.PIPE, text=True)
        self.addCleanup(process.stdout.close)
        self.addCleanup(process.wait, timeout=10)
        self.addCleanup(process.terminate)
        return process.stdout.readline().strip()

    def fleet(self, url):
        with urllib.request.urlopen(url + "fleet.json", timeout=10) as response:
            return json.load(response)

    def test_lifecycle_uses_actor_identity_and_keeps_late_stop_out_of_new_turn(self):
        self.hook("UserPromptSubmit", prompt="private text")
        self.assertFalse((self.repo / ".git/watchtower").exists())
        url = self.start_board()
        self.assertEqual(self.fleet(url)["codex"], [])
        self.hook("UserPromptSubmit", prompt="private text")
        self.hook("SubagentStart", agent_id="worker", agent_type="tower-scout")
        self.hook("PreModelRequest", session_id="worker", agent_id="worker", turn_id="agent-1", model="gpt-test")
        self.run_command([str(SCRIPTS / "tower-area.sh"), "add", "worker", "Test worktree", "--owns", "src"])
        self.run_command([str(SCRIPTS / "tower-area.sh"), "launch", "worker"])
        self.run_command([str(SCRIPTS / "tower-area.sh"), "step", "1", "2", "Testing"],
                         cwd=self.root / "repo-worker", env={**self.env, "CODEX_THREAD_ID": "worker"})
        board = self.fleet(url)
        actors = {actor["actor"]: actor for actor in board["codex"]}
        self.assertEqual(actors["root"]["state"], "working")
        self.assertEqual(actors["worker"]["worktree"], "repo-worker")
        self.assertEqual(actors["worker"]["model"], "gpt-test")
        self.assertEqual(board["areas"][0]["done"], 1)
        self.assertNotIn("private text", json.dumps(board))

        self.hook("SubagentStop", agent_id="worker", turn_id="agent-1")
        self.hook("UserPromptSubmit", turn_id="turn-2")
        self.hook("Stop", turn_id="turn-1")
        actors = {actor["actor"]: actor for actor in self.fleet(url)["codex"]}
        self.assertEqual(actors["root"]["state"], "working")
        self.assertEqual(actors["worker"]["state"], "idle")
        self.hook("Interrupt", turn_id="turn-2")
        self.assertEqual(next(a["state"] for a in self.fleet(url)["codex"] if a["actor"] == "root"), "interrupted")

    def test_board_does_not_serve_other_paths_or_hosts(self):
        url = self.start_board()
        with urllib.request.urlopen(url, timeout=10) as response:
            self.assertIn(b'<main id="board" data-codex>', response.read())
        requests = [url + "../fleet.json", url + ".git/config",
                    urllib.request.Request(url + "fleet.json", headers={"Host": "example.invalid"})]
        for request in requests:
            with self.assertRaises(urllib.error.HTTPError) as error:
                urllib.request.urlopen(request, timeout=10)
            with error.exception as response:
                self.assertEqual(response.code, 404)

    def test_install_is_idempotent_and_preserves_other_hooks(self):
        path = self.root / "hooks.json"
        original = {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "existing"}]}]}}
        path.write_text(json.dumps(original))
        command = [*COMMAND, "install", "--config", str(path)]
        self.run_command(command)
        installed = path.read_bytes()
        self.run_command(command)
        self.assertEqual(path.read_bytes(), installed)
        self.assertEqual(json.loads(installed)["hooks"]["Stop"][0], original["hooks"]["Stop"][0])
        self.assertIn("SubagentStart", json.loads(installed)["hooks"])


if __name__ == "__main__":
    unittest.main()
