"""Offline contract tests for the Garage pricing design preview.

The preview is intentionally unconnected to production or Stripe Checkout.
"""
from html.parser import HTMLParser
from pathlib import Path
import re
import unittest

PAGE = Path(__file__).resolve().parents[1] / "design/garage-pricing-preview/index.html"
TEXT = PAGE.read_text(encoding="utf-8")


class Elements(HTMLParser):
    def __init__(self):
        super().__init__()
        self.tags = []

    def handle_starttag(self, tag, attrs):
        self.tags.append((tag, dict(attrs)))


class GaragePricingPrototypeTest(unittest.TestCase):
    def test_unindexed_and_no_active_purchase_or_real_endpoints(self):
        self.assertIn('content="noindex,nofollow,noarchive"', TEXT)
        self.assertNotIn('checkout.stripe.com', TEXT)
        self.assertNotIn('api.stripe.com', TEXT)
        self.assertNotIn('sb_publishable_', TEXT)
        self.assertNotIn('price_1UPI', TEXT)
        self.assertNotIn('wqhymmtiawfwjikdaujo', TEXT)
        self.assertNotIn('fyestmquqvkdebxxbcky', TEXT)
        self.assertNotIn('window.location=', TEXT)
        self.assertNotIn('type="submit"', TEXT)
        nodes = Elements()
        nodes.feed(TEXT)
        buttons = [attrs for tag, attrs in nodes.tags
                   if tag == "button" and attrs.get("class") == "disabled"]
        self.assertEqual(3, len(buttons))
        self.assertTrue(all("disabled" in attrs for attrs in buttons))

    def test_price_matrix_and_billing_terms(self):
        for row in (
            "UK:{symbol:'£',monthly:[39,79,139],yearly:[390,790,1390]}",
            "EU:{symbol:'€',monthly:[45,89,159],yearly:[450,890,1590]}",
            "PL:{symbol:'zł',monthly:[99,219,399],yearly:[990,2190,3990]}",
        ):
            self.assertIn(row, TEXT)
        self.assertIn("annual/12", TEXT)
        self.assertIn("aria-pressed", TEXT)
        self.assertIn("before tax", TEXT)
        self.assertIn("przed podatkiem", TEXT)
        self.assertIn("0% booking commission", TEXT)
        self.assertIn("0% prowizji", TEXT)
        self.assertIn("is only a request", TEXT)
        self.assertIn("to propozycja", TEXT)

    def test_ui_controls_mobile_and_localization(self):
        parsed = Elements()
        parsed.feed(TEXT)
        ids = {attrs["id"] for _, attrs in parsed.tags if "id" in attrs}
        for key in ("language", "market", "monthly", "yearly", "starter-price",
                    "team-price", "pro-price", "starter-term", "team-term", "pro-term"):
            self.assertIn(key, ids)
        self.assertIn("@media(max-width:440px)", TEXT)
        self.assertIn("@media(max-width:820px)", TEXT)
        self.assertIn("document.documentElement.lang=lang", TEXT)
        self.assertIn("en:{status:", TEXT)
        self.assertIn("pl:{status:", TEXT)
        self.assertIn("role=\"group\"", TEXT)


if __name__ == "__main__":
    unittest.main()
