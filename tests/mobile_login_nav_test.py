"""Regression checks for the real mobile login link on both landing routes."""
from html.parser import HTMLParser
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
LOCALES = {"en", "pl", "de", "sk", "cs", "hu", "ro", "es", "fr", "it", "uk", "pt"}


class Parser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            self.links.append(dict(attrs))


class MobileLoginTest(unittest.TestCase):
    def test_mobile_login_routes_both_websites_to_existing_portal(self):
        for route in ("web/index.html", "web/start/index.html"):
            with self.subTest(route=route):
                content = (ROOT / route).read_text(encoding="utf-8")
                p = Parser()
                p.feed(content)
                matches = [link for link in p.links
                           if "nav-compact-login" in link.get("class", "").split()]
                self.assertEqual(len(matches), 1)
                self.assertEqual(matches[0]["href"], "/app/")
                self.assertNotIn('aria-label', matches[0])  # Accessible name follows translated visible text.
                self.assertIn('.nav-compact-login{display:none}', content)
                self.assertIn('@media(max-width:760px)', content)
                self.assertIn('min-height:44px', content)
                self.assertIn('nav-compact-label', content)
                self.assertIn('.nav-compact-label{font-size:12px;display:inline}', content)
                self.assertIn('flex-wrap:wrap', content)

                # Text content uses the same 12-language switching mechanism as
                # the rest of the landing page.
                start = content.find('class="nav-compact-label"')
                end = content.find('</span>', start)
                self.assertGreater(start, 0)
                span = content[start:end]
                for language in LOCALES:
                    self.assertIn(f'data-{language}="', span)

    def test_no_new_customer_booking_or_checkout_link_in_header(self):
        for route in ("web/index.html", "web/start/index.html"):
            content = (ROOT / route).read_text(encoding="utf-8")
            p = Parser()
            p.feed(content)
            matches = [link for link in p.links
                       if "nav-compact-login" in link.get("class", "").split()]
            self.assertNotIn("checkout", matches[0]["href"])
            self.assertNotIn("garage", matches[0]["href"])
            self.assertNotIn("booking", matches[0]["href"])


if __name__ == "__main__":
    unittest.main()
