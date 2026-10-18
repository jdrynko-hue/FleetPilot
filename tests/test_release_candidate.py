import tempfile
import json
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
        (self.site / "app/icons").mkdir()
        for size in (192, 512):
            (self.site / f"app/icons/Icon-{size}.png").write_bytes(b"synthetic test icon")
        (self.site / "app/manifest.json").write_text(json.dumps({
            "id": "/app/", "start_url": "/app/", "scope": "/app/",
            "icons": [
                {"src": f"icons/Icon-{size}.png", "sizes": f"{size}x{size}"}
                for size in (192, 512)
            ],
        }))
        for name in ("privacy", "terms"):
            (self.site / name).mkdir()
            (self.site / name / "index.html").write_text("<html>QA legal placeholder</html>")
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
            '<body><link rel="manifest" href="manifest.json">'
            '<script src="flutter_bootstrap.js"></script></body></html>'
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


    def test_missing_real_legal_page_fails_closed(self):
        (self.site / "terms/index.html").unlink()
        self.assertTrue(any("linked legal page" in issue for issue in validate(self.site)))

    def test_unsafe_pwa_scope_fails_closed(self):
        path = self.site / "app/manifest.json"
        manifest = json.loads(path.read_text())
        manifest["scope"] = "/"
        path.write_text(json.dumps(manifest))
        self.assertTrue(any("PWA scope" in issue for issue in validate(self.site)))

    def test_missing_pwa_icon_fails_closed(self):
        (self.site / "app/icons/Icon-192.png").unlink()
        self.assertTrue(any("Missing PWA icon" in issue for issue in validate(self.site)))

    def test_dotenv_bundling_fails_closed(self):
        (self.site / ".env.production").write_text("EXAMPLE=placeholder")
        self.assertTrue(any("Private-looking file" in issue for issue in validate(self.site)))

    def test_missing_compiled_asset_fails_closed(self):
        (self.site / "app/main.dart.js").unlink()
        self.assertTrue(any("main.dart.js" in issue for issue in validate(self.site)))


if __name__ == "__main__":
    unittest.main()
