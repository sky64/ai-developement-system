"""Exercise the exact inline workflow code offline; no credentials or network."""
import copy
import io
import json
from pathlib import Path
import tempfile
import textwrap
import unittest
from unittest.mock import patch

WORKFLOW = Path(__file__).resolve().parents[2] / ".github/workflows/codex-review.yml"
SOURCE = textwrap.dedent(WORKFLOW.read_text().split("        run: |\n", 1)[1])
SOURCE = SOURCE.split("python3 - <<'PY'\n", 1)[1].rsplit("\nPY", 1)[0]
CODE = {}
exec(compile(SOURCE, str(WORKFLOW), "exec"), CODE)  # Trusted local workflow, never PR content.
REPO = "sky64/ai-developement-system"


def fixture():
    pr = {
        "number": 4, "state": "open", "draft": False, "merged": False,
        "user": {"login": "Solvela-bot"},
        "head": {"sha": "a" * 40, "repo": {"full_name": REPO}},
        "base": {"sha": "b" * 40, "ref": "main", "repo": {"full_name": REPO}},
    }
    return {"action": "opened", "number": 4, "repository": {"full_name": REPO}, "pull_request": pr}


class Response(io.BytesIO):
    def __init__(self, data=b"", status=202):
        super().__init__(data)
        self.status = status


class GateTests(unittest.TestCase):
    def select(self, event, current=None, name="pull_request_target"):
        return CODE["select"](event, current if current is not None else event.get("pull_request"), name)

    def test_supported_actions_and_minimal_payload(self):
        for action in ("opened", "reopened", "ready_for_review", "synchronize"):
            event = fixture()
            event["action"] = action
            event["pull_request"]["title"] = "$(do-not-run)"
            payload = self.select(event)
            self.assertEqual(set(payload), {"schema", "repository", "number", "head", "base", "request_key"})
            self.assertEqual(payload["request_key"], f"{REPO}#4:{'a' * 40}:{'b' * 40}")

    def test_rejected_events(self):
        cases = []
        for action in ("closed", "edited", "labeled", "ping"):
            event = fixture()
            event["action"] = action
            cases.append(event)
        for path, value in [
            (("repository", "full_name"), "someone/else"),
            (("pull_request", "state"), "closed"),
            (("pull_request", "draft"), True),
            (("pull_request", "merged"), True),
            (("pull_request", "user", "login"), "attacker"),
            (("pull_request", "head", "repo", "full_name"), "attacker/fork"),
            (("pull_request", "base", "repo", "full_name"), "attacker/fork"),
            (("pull_request", "base", "ref"), "other"),
            (("pull_request", "head", "sha"), "$(id)"),
            (("pull_request", "base", "sha"), "A" * 40),
            (("number",), True),
            (("number",), 5),
            (("pull_request", "number"), True),
        ]:
            event = fixture()
            target = event
            for key in path[:-1]:
                target = target[key]
            target[path[-1]] = value
            cases.append(event)
        for event in cases:
            with self.subTest(event=event):
                self.assertIsNone(self.select(event))
        self.assertIsNone(self.select(fixture(), name="push"))
        self.assertIsNone(self.select({"zen": "ping"}))

    def test_current_github_truth_overrides_event(self):
        for side in ("head", "base"):
            event = fixture()
            current = copy.deepcopy(event["pull_request"])
            current[side]["sha"] = "c" * 40
            self.assertIsNone(self.select(event, current))
        for field, value in (("draft", True), ("state", "closed"), ("merged", True)):
            event = fixture()
            current = copy.deepcopy(event["pull_request"])
            current[field] = value
            self.assertIsNone(self.select(event, current))

    def run_main(self, event, current, webhook="https://example.invalid/private", failure=None, entry=False):
        requests = []
        self.requests = requests

        class Opener:
            def open(self, request, timeout):
                requests.append(request)
                if timeout != 10:
                    raise AssertionError("Expected bounded network timeout")
                if len(requests) == 1:
                    return Response(json.dumps(current).encode())
                if failure:
                    raise failure
                return Response()

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "event.json"
            path.write_text(json.dumps(event))
            with patch.dict(CODE["os"].environ, {
                "GITHUB_EVENT_PATH": str(path), "GITHUB_EVENT_NAME": "pull_request_target",
                "GH_READ_TOKEN": "synthetic-only", "REVIEW_WEBHOOK": webhook,
            }), patch.object(CODE["urllib"].request, "build_opener", return_value=Opener()):
                if entry:
                    exec(compile(SOURCE, str(WORKFLOW), "exec"), {"__name__": "__main__"})
                else:
                    CODE["main"]()
        return requests

    def test_transport_posts_only_minimal_json(self):
        event = fixture()
        requests = self.run_main(event, event["pull_request"])
        self.assertEqual(len(requests), 2)
        self.assertEqual(requests[0].full_url, f"https://api.github.com/repos/{REPO}/pulls/4")
        self.assertEqual(requests[1].method, "POST")
        self.assertNotIn("Authorization", requests[1].headers)
        self.assertEqual(json.loads(requests[1].data), self.select(event))

    def test_no_post_for_stale_or_closed_pr3(self):
        event = fixture()
        current = copy.deepcopy(event["pull_request"])
        current["head"]["sha"] = "c" * 40
        self.assertEqual(len(self.run_main(event, current)), 1)
        event["number"] = event["pull_request"]["number"] = current["number"] = 3
        current["state"], current["merged"] = "closed", True
        self.assertEqual(len(self.run_main(event, current)), 1)

    def test_invalid_event_makes_no_network_call(self):
        self.assertEqual(self.run_main({"zen": "ping"}, {}), [])

    def test_invalid_webhook_is_rejected(self):
        for target in ("", "http://example.invalid/private", "https://user:pass@example.invalid/private"):
            event = fixture()
            with self.subTest(target=target), self.assertRaises(ValueError):
                self.run_main(event, event["pull_request"], webhook=target)

    def test_post_failure_not_retried(self):
        event = fixture()
        error = OSError("ambiguous POST failure")
        with self.assertRaises(OSError):
            self.run_main(event, event["pull_request"], failure=error)
        self.assertEqual(len(self.requests), 2)

    def test_failure_output_does_not_reveal_url(self):
        event = fixture()
        output = io.StringIO()
        with patch("sys.stdout", output), self.assertRaises(SystemExit) as stopped:
            self.run_main(event, event["pull_request"], failure=OSError("https://example.invalid/private"), entry=True)
        self.assertEqual(stopped.exception.code, 1)
        self.assertNotIn("https://example.invalid/private", output.getvalue())
        self.assertEqual(len(self.requests), 2)

    def test_malformed_json_shape_fails_without_network(self):
        output = io.StringIO()
        with patch("sys.stdout", output), self.assertRaises(SystemExit):
            self.run_main([], {}, entry=True)
        self.assertEqual(self.requests, [])

    def test_redirects_are_disabled(self):
        self.assertIsNone(CODE["NoRedirect"]().redirect_request(None, None, 302, "", {}, "https://other.invalid"))

    def test_workflow_has_no_checkout_or_expression_in_script(self):
        workflow = WORKFLOW.read_text()
        self.assertNotIn("uses:", workflow)
        self.assertNotIn("${{", SOURCE)
        self.assertIn("pull-requests: read", workflow)
        self.assertIn("timeout-minutes: 2", workflow)


if __name__ == "__main__":
    unittest.main()
