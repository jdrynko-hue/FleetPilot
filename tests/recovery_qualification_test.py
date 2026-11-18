import hashlib
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import prepare_marketing_release as release
import qualify_recovered_baseline as qualification


class RecoveryQualificationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        home = b'<html><base href="$FLUTTER_BASE_HREF">Flotaryx marketing</html>'
        portal = b'<html><base href="$FLUTTER_BASE_HREF">Flotaryx app</html>'
        self.sources = {"index.html": home, "app/index.html": portal, "CNAME": b"flotaryx.com\n"}
        self.evidence = {"source_web": []}
        for name, data in self.sources.items():
            blob = b"blob " + str(len(data)).encode() + b"\0" + data
            self.evidence["source_web"].append({
                "path": "web/" + name, "size_bytes": len(data),
                "git_blob": hashlib.sha1(blob, usedforsecurity=False).hexdigest(),
            })
        for name, (entry, base) in qualification.source_aliases(self.evidence).items():
            data = self.sources[entry["path"][4:]]
            if base:
                data = data.replace(b'<base href="$FLUTTER_BASE_HREF">',
                                    ('<base href="' + base + '">').encode())
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)

    def test_app_entrypoint_is_proved_against_original_portal_not_marketing_source(self):
        self.assertEqual(qualification.verify_source(self.root, self.evidence), 5)
        self.assertIn(b"Flotaryx app", (self.root / "app/index.html").read_bytes())

    def test_changed_source_backed_file_fails_independent_git_blob_proof(self):
        (self.root / "app/index.html").write_bytes(b"<html>Different app</html>")
        with self.assertRaises(release.PreparationError):
            qualification.verify_source(self.root, self.evidence)

    def test_unverified_archive_digest_fails_before_any_manifest_is_created(self):
        archive = self.root / "capture.zip"
        archive.write_bytes(b"untrusted")
        output = self.root / "qualified.json"
        with self.assertRaises(release.PreparationError):
            qualification.qualify(capture=self.root, source_inventory=self.root / "none",
                                  artifact_archive=archive, artifact_sha256="0" * 64,
                                  capture_run=1, capture_artifact=2, output=output)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()

