#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("recovery", ROOT / "tools/recover_marketing_baseline.py")
recovery = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = recovery
spec.loader.exec_module(recovery)


class Response:
    def __init__(self, data=b"abc", url="https://flotaryx.com/app/main.dart.js", headers=None):
        self.status = 200
        self.url = url
        self.headers = headers or {"ETag": '"pinned"', "Last-Modified": "expected", "Content-Length": str(len(data))}
        self.data = data

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def read(self, limit):
        return self.data[:limit]


class Opener:
    def __init__(self, response):
        self.response = response

    def open(self, request, timeout):
        if request.method != "GET" or request.full_url != "https://flotaryx.com/app/main.dart.js":
            raise AssertionError("Unexpected mutation or URL")
        return self.response


class RecoverySnapshotTests(unittest.TestCase):
    def test_pinned_archive_has_every_original_file_including_hidden_metadata(self):
        evidence = recovery.load_inventory(ROOT / "docs/releases/2026-10-17-production-inventory.json")
        self.assertEqual(len(evidence["files"]), 161)
        self.assertIn("app/.last_build_id", evidence["files"])
        self.assertEqual(sum(x.startswith("app/") for x in evidence["files"]), 97)

    def test_path_escape_and_encoded_escape_are_rejected(self):
        for value in ("../secret", "app/../secret", "/etc/passwd", "app//index.html",
                      "app/%2e%2e/secret", "https://example.com", "app/./index.html"):
            with self.subTest(value=value), self.assertRaises(recovery.CaptureError):
                recovery.file_path(value)

    def test_duplicate_inventory_and_missing_required_file_are_rejected(self):
        original = json.loads((ROOT / "docs/releases/2026-10-17-production-inventory.json").read_text())
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "inventory.json"
            for files in (original["files"] + [original["files"][0]],
                          [x for x in original["files"] if x != "app/main.dart.js"]):
                path.write_text(json.dumps({**original, "files": files}))
                with self.assertRaises(recovery.CaptureError):
                    recovery.load_inventory(path)

    def test_wrong_source_commit_is_rejected_before_reading_source(self):
        with patch.object(recovery, "git_read", return_value=b"wrong\n"):
            with self.assertRaises(recovery.CaptureError):
                recovery.source_expectations("unused", {"source_commit": "a" * 40})

    def test_cross_origin_and_other_file_redirects_are_rejected(self):
        handler = recovery.SameFileRedirect("app/main.dart.js")
        for url in ("http://flotaryx.com/app/main.dart.js", "https://other.test/app/main.dart.js",
                    "https://flotaryx.com/private", "https://flotaryx.com/app/main.dart.js?other=1"):
            with self.subTest(url=url), self.assertRaises(recovery.CaptureError):
                handler.redirect_request(Request("https://flotaryx.com/app/main.dart.js"),
                                         None, 302, "Found", {}, url)

    def test_valid_capture_preserves_original_bytes(self):
        with patch.object(recovery, "build_opener", return_value=Opener(Response())):
            captured = recovery.fetch_public_file("app/main.dart.js", "expected")
        self.assertEqual(captured.content, b"abc")

    def test_deployment_change_and_truncated_response_are_rejected(self):
        variants = (
            {"ETag": '"pinned"', "Last-Modified": "new-deploy", "Content-Length": "3"},
            {"ETag": '"pinned"', "Last-Modified": "expected", "Content-Length": "9"},
            {"ETag": '"pinned"', "Last-Modified": "expected", "Content-Encoding": "gzip"},
        )
        for headers in variants:
            with self.subTest(headers=headers), patch.object(
                    recovery, "build_opener", return_value=Opener(Response(headers=headers))):
                with self.assertRaises(recovery.CaptureError):
                    recovery.fetch_public_file("app/main.dart.js", "expected")

    def test_html_error_instead_of_javascript_is_rejected(self):
        with patch.object(recovery, "build_opener", return_value=Opener(Response(b"<!doctype html><h1>404</h1>"))):
            with self.assertRaises(recovery.CaptureError):
                recovery.fetch_public_file("app/main.dart.js", "expected")

    def test_source_mismatch_is_rejected(self):
        with patch.object(recovery, "fetch_public_file", return_value=recovery.Captured(b"changed", "e", "d")):
            with self.assertRaises(recovery.CaptureError):
                recovery.capture_file("index.html", "d", {"index.html": b"original"})

    def test_only_cname_metadata_can_fall_back_to_pinned_git_after_404(self):
        error = HTTPError("https://flotaryx.com/CNAME", 404, "Not found", {}, None)
        with patch.object(recovery, "fetch_public_file", side_effect=error):
            captured = recovery.capture_file("CNAME", "d", {"CNAME": b"flotaryx.com\n"})
            self.assertEqual(captured.source, "deployed_git_cname")
            self.assertEqual(captured.content, b"flotaryx.com\n")
            with self.assertRaises(HTTPError):
                recovery.capture_file("app/.last_build_id", "d", {"app/.last_build_id": b"do-not-invent"})

    def test_changed_content_or_etag_in_second_pass_is_rejected(self):
        original = recovery.Captured(b"original", "etag", "date")
        recovery.verify_second_capture(original, original)
        for second in (recovery.Captured(b"changed", "etag", "date"),
                       recovery.Captured(b"original", "new-etag", "date")):
            with self.assertRaises(recovery.CaptureError):
                recovery.verify_second_capture(original, second)

    def test_missing_file_never_produces_a_complete_site(self):
        evidence = {"files": ["app/main.dart.js", "index.html"],
                    "public_last_modified": "date", "deployment_run_id": 123,
                    "source_commit": "a" * 40}
        def fake_read(name, *_):
            if name.startswith("app/"):
                raise recovery.CaptureError("Synthetic unavailable protected app file")
            return recovery.Captured(b"index", "e", "date")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            inventory = root / "source.json"
            inventory.write_text("{}")
            output = root / "capture"
            with patch.object(recovery, "load_inventory", return_value=evidence), \
                 patch.object(recovery, "source_expectations", return_value={}), \
                 patch.object(recovery, "capture_file", side_effect=fake_read):
                with self.assertRaises(recovery.CaptureError):
                    recovery.capture(inventory, root, output)
            self.assertFalse((output / "site").exists())
            self.assertFalse((output / "capture-manifest.json").exists())
            report = json.loads((output / "capture-report.json").read_text())
            self.assertEqual(report["status"], "INCOMPLETE_CAPTURE")
            self.assertFalse(report["same_bytes_in_two_complete_passes"])


if __name__ == "__main__":
    unittest.main()

