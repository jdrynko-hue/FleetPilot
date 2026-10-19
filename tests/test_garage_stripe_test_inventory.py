import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from check_garage_stripe_test_inventory import (
    REQUIRED_EVENTS, verify_inventory
)

QA_URL = "https://fyestmquqvkdebxxbcky.supabase.co/functions/v1/flotaryx-garage-test-webhook"
PROD_URL = "https://wqhymmtiawfwjikdaujo.supabase.co/functions/v1/flotaryx-garage-test-webhook"


def valid_inventory():
    return {
        "livemode": False,
        "products": [{"id": "prod_fixture", "name": "Flotaryx Garage",
                      "active": True}],
        "prices": [
            {"product": "prod_fixture", "active": True, "currency": currency,
             "interval": interval, "unit_amount": 2500, "type": "recurring",
             "recurring": {"interval": interval, "interval_count": 1},
             "livemode": False}
            for currency in ("gbp", "eur", "pln")
            for interval in ("month", "year")
        ],
        "webhook_endpoints": [{
            "enabled": True, "url": QA_URL,
            "enabled_events": sorted(REQUIRED_EVENTS),
        }],
    }


class StripeGarageTestPreflight(unittest.TestCase):
    def test_isolated_sandbox_ready_shape_only(self):
        self.assertEqual(verify_inventory(valid_inventory()), [])

    def test_any_livemode_input_fails(self):
        for value in (True, None, "false", 0):
            data = valid_inventory()
            data["livemode"] = value
            self.assertTrue(any("Test-mode" in e for e in verify_inventory(data)))

    def test_existing_fleet_only_catalog_fails(self):
        data = valid_inventory()
        data["products"][0]["name"] = "Flotaryx Pro"
        errors = verify_inventory(data)
        self.assertTrue(any("No active Garage" in e for e in errors))
        self.assertTrue(any("Missing Garage" in e for e in errors))

    def test_missing_currency_interval_fails(self):
        data = valid_inventory()
        data["prices"] = data["prices"][:-1]
        self.assertTrue(any("pln/year" in e for e in verify_inventory(data)))

    def test_missing_or_zero_amount_fails(self):
        data = valid_inventory()
        data["prices"][0]["unit_amount"] = None
        self.assertTrue(any("gbp/month" in e for e in verify_inventory(data)))
        data["prices"][0]["unit_amount"] = 0
        self.assertTrue(any("gbp/month" in e for e in verify_inventory(data)))

    def test_test_mode_webhook_pointing_to_production_fails(self):
        data = valid_inventory()
        data["webhook_endpoints"][0]["url"] = PROD_URL
        errors = verify_inventory(data)
        self.assertTrue(any("production Supabase" in e for e in errors))
        self.assertTrue(any("exactly one" in e for e in errors))

    def test_extra_production_webhook_also_fails(self):
        data = valid_inventory()
        data["webhook_endpoints"].append({
            "enabled": True, "url": PROD_URL,
            "enabled_events": sorted(REQUIRED_EVENTS),
        })
        self.assertTrue(any("production Supabase" in e
                            for e in verify_inventory(data)))

    def test_missing_signed_reconciliation_events_fails(self):
        data = valid_inventory()
        data["webhook_endpoints"][0]["enabled_events"].remove("invoice.payment_failed")
        self.assertTrue(any("invoice.payment_failed" in e
                            for e in verify_inventory(data)))

    def test_disabled_qa_webhook_fails(self):
        data = valid_inventory()
        data["webhook_endpoints"][0]["enabled"] = False
        self.assertTrue(any("exactly one" in e for e in verify_inventory(data)))

    def test_url_credential_or_query_fails(self):
        for url in (
            "http://fyestmquqvkdebxxbcky.supabase.co/functions/v1/flotaryx-garage-test-webhook",
            QA_URL + "?secret=bad",
            "https://user:pass@fyestmquqvkdebxxbcky.supabase.co/functions/v1/flotaryx-garage-test-webhook",
        ):
            data = valid_inventory()
            data["webhook_endpoints"][0]["url"] = url
            self.assertTrue(verify_inventory(data))

    def test_reject_one_time_and_multi_interval_price(self):
        for mutation in ({"type": "one_time"}, {"recurring": {"interval": "month", "interval_count": 3}}, {"livemode": True}):
            data = valid_inventory()
            data["prices"][0].update(mutation)
            self.assertTrue(any("gbp/month" in e for e in verify_inventory(data)))

    def test_reject_extra_webhook_events(self):
        data = valid_inventory()
        data["webhook_endpoints"][0]["enabled_events"].append("*")
        self.assertTrue(any("wildcard" in e for e in verify_inventory(data)))

    def test_schema_invalid_fails(self):
        self.assertTrue(verify_inventory({"livemode": False}))
        self.assertTrue(verify_inventory([]))


if __name__ == "__main__":
    unittest.main()
