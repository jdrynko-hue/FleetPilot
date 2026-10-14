#!/usr/bin/env python3
"""Staging-only website guard: Fleet remains live while Garage is advertised as planned.

No browser automation, network or production credentials are needed.
"""
from html.parser import HTMLParser
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ("pl", "en", "de", "sk", "cs", "hu", "ro", "es", "fr", "it", "uk", "pt")


class Elements(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.nodes = []
        self.stack = []

    def handle_starttag(self, tag, attrs):
        props = dict(attrs)
        self.nodes.append((tag, props))
        if tag not in ("meta", "link", "base", "br", "img", "input", "hr", "source"):
            self.stack.append(tag)

    def handle_endtag(self, tag):
        if tag in self.stack:
            while self.stack:
                if self.stack.pop() == tag:
                    break


class WebsiteEcosystemPreviewTest(unittest.TestCase):
    def test_source_and_generated_homepage_have_consistent_safe_previews(self):
        for name in ("web/start/index.html", "web/index.html"):
            with self.subTest(name=name):
                html = (ROOT / name).read_text(encoding="utf-8")
                self.assertEqual(html.count('id="ecosystem"'), 1)
                self.assertEqual(html.count('href="#ecosystem"'), 1)
                self.assertLess(html.index('class="hero"'),
                                html.index('id="ecosystem"'))
                self.assertLess(html.index('id="ecosystem"'),
                                html.index('id="industries"'))
                self.assertEqual(html.count('class="ecosystem-card"'), 3)
                self.assertEqual(html.count('class="ecosystem-bridge"'), 1)
                self.assertIn('class="notice ecosystem-status"', html)
                self.assertIn("Garage, marketplace bookings", html)
                self.assertIn("Garage, rezerwacje dla klientów", html)
                self.assertIn("in development", html)
                self.assertIn("Garage Ecosystem", html)
                self.assertIn("upcoming Flotaryx Garage", html)
                self.assertGreaterEqual(html.count('href="/app/"'), 3)
                self.assertIn('id="site-language"', html)
                self.assertIn("@media(max-width:760px){.ecosystem-grid{grid-template-columns:1fr}",
                              html)
                self.assertEqual(html.count(".ecosystem-grid{display:grid"), 1)
                self.assertTrue(all(f'id="{id}"' in html for id in (
                    "industries", "features", "how", "roles", "benefits", "faq")))
                preview = html.split('<section class="section ecosystem-section"', 1)[1].split(
                    '<section class="section" id="industries">', 1)[0]
                self.assertNotIn('href="/app/"', preview)
                self.assertNotIn("stripe.com", preview.lower())
                self.assertNotIn("checkout", preview.lower())
                self.assertNotIn("onclick=", preview.lower())
                self.assertNotIn("<form", preview.lower())

                parsed = Elements()
                parsed.feed(preview)
                cards = [a for tag, a in parsed.nodes
                         if tag == "article" and a.get("class") == "ecosystem-card"]
                self.assertEqual(len(cards), 3)
                translated = [(tag, attrs) for tag, attrs in parsed.nodes
                              if "data-en" in attrs]
                self.assertGreaterEqual(len(translated), 12)
                for tag, attrs in translated:
                    for lang in LANGUAGES:
                        self.assertTrue(attrs.get(f"data-{lang}"),
                                        f"{name}: {tag} lacks {lang} copy")
                    self.assertTrue(attrs["data-en"].strip())
                    self.assertTrue(attrs["data-pl"].strip())
                self.assertIn('document.querySelectorAll(\\'[data-en][data-pl]\\')', html)

    def test_source_remains_prelaunch_and_release_workflow_unchanged(self):
        workflow = (ROOT / ".github/workflows/flotaryx-homepage-release.yml").read_text()
        self.assertIn("branches: [main]", workflow)
        self.assertIn("workflow_dispatch", workflow)
        self.assertIn("web / 'start' / 'index.html'", workflow)
        for name in ("web/start/index.html", "web/index.html"):
            content = (ROOT / name).read_text()
            self.assertRegex(content, r'property="og:description"[^\\n]+upcoming Flotaryx Garage')
            self.assertIn("Garage (coming soon)", content)
            self.assertIn('data-pl="Znajdź mechanika"', content)


if __name__ == "__main__":
    unittest.main()
