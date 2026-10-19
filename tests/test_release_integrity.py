"""Unit tests for integrity of a built, unpublished QA release candidate."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from release_integrity import MANIFEST, inventory, verify_manifest, write_manifest

COMMIT = "a" * 40


class QaReleaseIntegrityTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        (self.root / "app").mkdir()
        (self.root / "index.html").write_text("Unpublished QA landing", encoding="utf-8")
        (self.root / "app/main.dart.js").write_bytes(b"compiled fixture")

    def test_write_and_verify(self):
        write_manifest(self.root, COMMIT)
        verify_manifest(self.root, COMMIT)
        doc = json.loads((self.root / MANIFEST).read_text())
        self.assertEqual(doc["kind"], "flotaryx-qa-unpublished-only")
        self.assertIs(doc["deployment_authorized"], False)
        self.assertEqual(doc["source_commit"], COMMIT)
        self.assertEqual(sorted(doc["files"]), ["app/main.dart.js", "index.html"])

    def test_same_files_have_deterministic_manifest(self):
        write_manifest(self.root, COMMIT)
        expected = (self.root / MANIFEST).read_bytes()
        (self.root / MANIFEST).unlink()
        write_manifest(self.root, COMMIT)
        self.assertEqual((self.root / MANIFEST).read_bytes(), expected)

    def test_modification_fails(self):
        write_manifest(self.root, COMMIT)
        (self.root / "app/main.dart.js").write_bytes(b"tampered")
        with self.assertRaisesRegex(ValueError, "do not match"):
            verify_manifest(self.root, COMMIT)

    def test_missing_file_fails(self):
        write_manifest(self.root, COMMIT)
        (self.root / "index.html").unlink()
        with self.assertRaisesRegex(ValueError, "do not match"):
            verify_manifest(self.root, COMMIT)

    def test_extra_file_fails(self):
        write_manifest(self.root, COMMIT)
        (self.root / "extra-secret.txt").write_text("added later")
        with self.assertRaisesRegex(ValueError, "do not match"):
            verify_manifest(self.root, COMMIT)

    def test_different_commit_fails(self):
        write_manifest(self.root, COMMIT)
        with self.assertRaisesRegex(ValueError, "do not match"):
            verify_manifest(self.root, "b" * 40)

    def test_flag_changed_fails(self):
        write_manifest(self.root, COMMIT)
        path = self.root / MANIFEST
        doc = json.loads(path.read_text())
        doc["deployment_authorized"] = True
        path.write_text(json.dumps(doc))
        with self.assertRaisesRegex(ValueError, "do not match"):
            verify_manifest(self.root, COMMIT)

    def test_second_write_fails(self):
        write_manifest(self.root, COMMIT)
        with self.assertRaisesRegex(ValueError, "already exist"):
            write_manifest(self.root, COMMIT)

    def test_invalid_commit_fails(self):
        with self.assertRaisesRegex(ValueError, "40-character"):
            write_manifest(self.root, "../invalid")

    def test_symlink_fails(self):
        destination = self.root / "index.html"
        link = self.root / "app/link.html"
        try:
            link.symlink_to(destination)
        except (OSError, NotImplementedError):
            self.skipTest("Symlinks unavailable on this filesystem")
        with self.assertRaisesRegex(ValueError, "symlink"):
            inventory(self.root)

    def test_absent_manifest_fails(self):
        with self.assertRaisesRegex(ValueError, "missing"):
            verify_manifest(self.root, COMMIT)

    def test_invalid_json_fails(self):
        (self.root / MANIFEST).write_text("{not-json")
        with self.assertRaisesRegex(ValueError, "Invalid release manifest"):
            verify_manifest(self.root, COMMIT)


if __name__ == "__main__":
    unittest.main()
