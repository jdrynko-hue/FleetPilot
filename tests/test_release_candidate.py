import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from verify_release_candidate import validate


class ReleaseArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.site = Path(self.temp.name)
        (self.site / "app").mkdir()
        (self.site / "CNAME").write_text("flotaryx.com\n")
        (self.site / "index.html").write_text(
            '<!doctype html><html><head><base href="/"></head><body>'
            '<a href="/app/?portal=fleet">Fleet</a>'
            '<a href="/app/?portal=garage">Garage</a>'
            '<a href="/app/?portal=search">Booking</a>'
            '<a href="/privacy/">Privacy</a><a href="/terms/">Terms</a>'
            '</body></html>'
        )
        (self.site / "app/index.html").write_text(
            '<!doctype html><html><head><base href="/app/"></head>'
            '<body><script src="flutter_bootstrap.js"></script></body></html>'
        )
        (self.site / "app/flutter_bootstrap.js").write_text("bootstrap();")
        (self.site / "app/main.dart.js").write_text("main();")

    def test_valid_static_artifact(self):
        self.assertEqual(validate(self.site), [])

    def test_missing_portal_entry_fails_closed(self):
        homepage = self.site / "index.html"
        homepage.write_text(homepage.read_text().replace('portal=garage', 'portal=other'))
        self.assertTrue(any("garage" in issue for issue in validate(self.site)))

    def test_missing_legal_link_fails_closed(self):
        homepage = self.site / "index.html"
        homepage.write_text(homepage.read_text().replace("/privacy/", "/other/"))
        self.assertTrue(any("privacy" in issue for issue in validate(self.site)))

    def test_wrong_portal_base_fails_closed(self):
        portal = self.site / "app/index.html"
        portal.write_text(portal.read_text().replace('href="/app/"', 'href="/"'))
        self.assertTrue(any("base href" in issue for issue in validate(self.site)))

    def test_private_key_in_compiled_js_fails_closed(self):
        (self.site / "app/main.dart.js").write_text("const privateValue='sk_test_123456789abc';")
        self.assertTrue(any("credential" in issue for issue in validate(self.site)))

    def test_live_key_in_marketing_fails_closed(self):
        (self.site / "marketing.js").write_text("const privateValue='sk_live_123456789abc';")
        self.assertTrue(any("credential" in issue for issue in validate(self.site)))

    def test_missing_compiled_asset_fails_closed(self):
        (self.site / "app/main.dart.js").unlink()
        self.assertTrue(any("main.dart.js" in issue for issue in validate(self.site)))


if __name__ == "__main__":
    unittest.main()
