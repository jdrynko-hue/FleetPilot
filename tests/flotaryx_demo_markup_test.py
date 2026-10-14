#!/usr/bin/env python3
"""Zero-network regression checks for staged, self-contained Flotaryx demo."""
from html.parser import HTMLParser
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HTML = ROOT / "web/demo/index.html"

class Markup(HTMLParser):
    def __init__(self):
        super().__init__()
        self.nodes = []
    def handle_starttag(self, tag, attrs):
        self.nodes.append((tag, dict(attrs)))

class DemoTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.html = HTML.read_text(encoding="utf-8")
        parser = Markup()
        parser.feed(cls.html)
        cls.nodes = parser.nodes

    def test_four_views_and_navigation_are_local_and_noscript_safe(self):
        views = [attrs for tag, attrs in self.nodes
                 if tag == "section" and "view" in attrs.get("class","").split()]
        roles = {"fleet", "garage", "mechanic", "customer"}
        self.assertEqual({row["id"] for row in views}, roles)
        links = [attrs for tag, attrs in self.nodes
                 if tag == "a" and "data-role" in attrs]
        self.assertEqual({a["data-role"] for a in links}, roles)
        self.assertTrue(all(a["href"] == "#"+a["data-role"] for a in links))
        self.assertIn(".view:target{display:block}", self.html)
        self.assertIn("<noscript>", self.html)
        self.assertIn('name="viewport"', self.html)

    def test_end_to_end_demo_controls_exist(self):
        actions = {a["data-action"] for tag,a in self.nodes
                   if tag == "button" and "data-action" in a}
        self.assertEqual(actions, {
            "send","quote","approve","start","complete","request","confirm"
        })
        ids = [v["id"] for tag,v in self.nodes if "id" in v]
        self.assertEqual(len(ids),len(set(ids)),"duplicate DOM IDs")
        for key in ["fleetStatus","garageStatus","mechanicStatus",
                    "garageBookingStatus","customerStatus","historyList",
                    "garageHistory","toast","reset","estimate","slot","service"]:
            self.assertIn(key,ids)

    def test_no_prod_credentials_payments_or_external_imports(self):
        self.assertIn('name="robots" content="noindex,nofollow"', self.html)
        self.assertNotRegex(self.html, r"https?://")
        self.assertNotIn("supabase.co", self.html.lower())
        self.assertNotIn("checkout.stripe", self.html.lower())
        self.assertNotIn("fetch(", self.html)
        self.assertNotIn("XMLHttpRequest", self.html)
        self.assertNotIn("localStorage", self.html)
        self.assertNotIn("sessionStorage", self.html)
        self.assertNotIn("navigator.sendBeacon", self.html)
        self.assertNotIn("new WebSocket", self.html)
        self.assertNotIn('type="submit"', self.html)
        self.assertRegex(self.html,r"fikcyjne")
        self.assertTrue(all("src" not in attrs for tag,attrs in self.nodes if tag=="script"))
        self.assertEqual(len([tag for tag,attrs in self.nodes if tag=="form"]),0)

    def test_javascript_syntax_is_valid(self):
        scripts = re.findall(r"<script(?:\s[^>]*)?>([\s\S]*?)</script>",self.html)
        self.assertGreaterEqual(len(scripts),1)
        for js in scripts:
            with tempfile.NamedTemporaryFile(mode="w",suffix=".js",encoding="utf-8") as f:
                f.write(js)
                f.flush()
                subprocess.run(["node","--check",f.name],check=True,capture_output=True)

    def test_stages_and_mobile_layout_are_present(self):
        self.assertIn("@media(max-width:480px)",self.html)
        self.assertIn(".role-nav",self.html)
        self.assertIn("grid-template-columns:1fr",self.html)
        for phase in ("reported","sent","quoted","approved","repairing","completed"):
            self.assertIn(phase,self.html)
        for booking in ("none","requested","confirmed"):
            self.assertIn(booking,self.html)

if __name__=="__main__":
    unittest.main()
