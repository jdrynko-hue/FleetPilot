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
                                html.index('id="features"'))
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
                    "garage", "booking", "features", "how", "offer", "faq")))
                preview = html.split('<section class="section ecosystem-section"', 1)[1].split(
                    '</section>', 1)[0]
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
                self.assertIn("document.querySelectorAll('[data-en][data-pl]')", html)

    def test_source_remains_prelaunch(self):
        for name in ("web/start/index.html", "web/index.html"):
            content = (ROOT / name).read_text()
            self.assertRegex(content, r'property="og:description"[^\n]+upcoming Flotaryx Garage')
            self.assertIn("Garage (coming soon)", content)
            self.assertIn('data-pl="Znajdź mechanika"', content)

    def test_skip_link_precedes_navigation_and_targets_focusable_main(self):
        for name in ("web/index.html", "web/start/index.html"):
            with self.subTest(name=name):
                html = (ROOT / name).read_text()
                parsed = Elements()
                parsed.feed(html)
                links = [a for t, a in parsed.nodes if t == 'a']
                self.assertEqual(links[0].get('class'), 'skip-link')
                self.assertEqual(links[0].get('href'), '#main-content')
                mains = [a for t, a in parsed.nodes if t == 'main']
                self.assertEqual(len(mains), 1)
                self.assertEqual(mains[0].get('id'), 'main-content')
                self.assertEqual(mains[0].get('tabindex'), '-1')
                for language in LANGUAGES:
                    self.assertTrue(links[0].get('data-' + language))

    def test_both_routes_ship_the_same_design(self):
        root = (ROOT / "web/index.html").read_text()
        start = (ROOT / "web/start/index.html").read_text()
        self.assertEqual(start, root.replace('$FLUTTER_BASE_HREF', '/'))

    def test_navigation_and_translations_are_complete(self):
        for name in ("web/index.html", "web/start/index.html"):
            with self.subTest(name=name):
                parsed = Elements()
                parsed.feed((ROOT / name).read_text())
                ids = [a['id'] for _, a in parsed.nodes if 'id' in a]
                self.assertEqual(len(ids), len(set(ids)), 'Duplicate anchor IDs')
                for tag, attrs in parsed.nodes:
                    href = attrs.get('href', '')
                    if href.startswith('#') and len(href) > 1:
                        self.assertIn(href[1:], ids, f'Broken anchor: {href}')
                    if 'data-en' in attrs:
                        for language in LANGUAGES:
                            self.assertTrue(attrs.get('data-' + language, '').strip(),
                                            f'{name}: {tag} lacks {language}')

    def test_product_previews_are_labeled_and_accessible(self):
        html = (ROOT / 'web/index.html').read_text()
        self.assertIn('fictional examples, not screenshots of the live app', html)
        self.assertIn('Purchasing is not available on this page.', html)
        parsed = Elements()
        parsed.feed(html)
        buttons = {a['data-preview']: a for t, a in parsed.nodes
                   if t == 'button' and 'data-preview' in a}
        panels = {a['data-preview-panel']: a for _, a in parsed.nodes
                  if 'data-preview-panel' in a}
        self.assertEqual(set(buttons), {'fleet', 'garage', 'driver'})
        self.assertEqual(set(panels), set(buttons))
        for name, button in buttons.items():
            self.assertEqual(button['type'], 'button')
            self.assertEqual(button['aria-controls'], panels[name]['id'])
            self.assertEqual(button['aria-pressed'], str(name == 'fleet').lower())
            self.assertEqual('hidden' in panels[name], name != 'fleet')


if __name__ == "__main__":
    unittest.main()
