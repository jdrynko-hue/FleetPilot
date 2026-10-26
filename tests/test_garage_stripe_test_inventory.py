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
    # Synthetic Stripe prices and DB records; never real test/live customer data.
    prices = [
        {"id": f"price_fixture_{currency}_{interval}",
         "product": "prod_fixture", "active": True, "livemode": False,
         "currency": currency, "interval": interval, "unit_amount": 2500,
         "type": "recurring", "billing_scheme": "per_unit",
         "metadata": {"product": "garage", "plan_code": "garage_basic"},
         "recurring": {"interval": interval, "interval_count": 1,
                       "usage_type": "licensed"}}
        for currency in ("gbp", "eur", "pln")
        for interval in ("month", "year")
    ]
    catalog = [
        {"plan_code": "garage_basic", "currency": p["currency"],
         "billing_interval": p["interval"], "stripe_price_id": p["id"],
         "amount_minor": p["unit_amount"], "active": True}
        for p in prices
    ]
    return {
        "livemode": False,
        "qa_catalog": catalog,
        "products": [{"id": "prod_fixture", "name": "Flotaryx Garage",
                      "active": True}],
        "prices": prices,
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

    def test_malformed_webhook_port_and_events_fail_closed(self):
        for url in (QA_URL.replace(".supabase.co/", ".supabase.co:bad/"),
                    QA_URL.replace("https://", "https://[::1")):
            data = valid_inventory()
            data["webhook_endpoints"][0]["url"] = url
            self.assertTrue(verify_inventory(data))
        data = valid_inventory()
        data["webhook_endpoints"][0]["enabled_events"].append(None)
        self.assertTrue(any("invalid entries" in e for e in verify_inventory(data)))

    def test_qa_catalog_absent_or_empty_blocks_checkout(self):
        data = valid_inventory()
        data.pop("qa_catalog")
        self.assertTrue(any("Missing sanitized QA catalog" in e
                            for e in verify_inventory(data)))
        data["qa_catalog"] = []
        self.assertTrue(any("Missing verified QA catalog prices" in e
                            for e in verify_inventory(data)))

    def test_qa_catalog_amount_mismatch_fails_closed(self):
        data = valid_inventory()
        data["qa_catalog"][0]["amount_minor"] = 2900
        self.assertTrue(any("differs" in e for e in verify_inventory(data)))

    def test_qa_catalog_price_id_cannot_point_to_fleet_price(self):
        data = valid_inventory()
        data["products"].append({"id": "prod_fleet", "name": "Flotaryx Fleet",
                                  "active": True})
        data["prices"].append({
            **data["prices"][0], "id": "price_fleet",
            "product": "prod_fleet"})
        data["qa_catalog"][0]["stripe_price_id"] = "price_fleet"
        self.assertTrue(any("differs" in e for e in verify_inventory(data)))

    def test_qa_catalog_duplicate_mapping_rejected(self):
        data = valid_inventory()
        data["qa_catalog"].append(dict(data["qa_catalog"][0]))
        self.assertTrue(any("Duplicate" in e for e in verify_inventory(data)))

    def test_qa_catalog_invalid_amounts_and_price_types(self):
        for invalid in (True, None, 0, -1, "2500"):
            data = valid_inventory()
            data["qa_catalog"][0]["amount_minor"] = invalid
            self.assertTrue(any("Malformed active" in e
                                for e in verify_inventory(data)))

    def test_qa_catalog_rejects_test_price_livemode_true(self):
        data = valid_inventory()
        data["prices"][0]["livemode"] = True
        self.assertTrue(any("differs" in e for e in verify_inventory(data)))

    def test_qa_catalog_rejects_price_currency_interval_or_status_change(self):
        for change in ({"currency": "usd"}, {"active": False},
                       {"recurring": {"interval": "year", "interval_count": 1}}):
            data = valid_inventory()
            data["prices"][0].update(change)
            self.assertTrue(any("differs" in e for e in verify_inventory(data)))

    def test_qa_catalog_rejects_malformed_and_duplicate_rows(self):
        for value in ("not-a-row", None, 42):
            data = valid_inventory()
            data["qa_catalog"].append(value)
            self.assertTrue(any("Malformed QA catalog row" in e
                                for e in verify_inventory(data)))
        data = valid_inventory()
        data["qa_catalog"][1]["stripe_price_id"] = data["qa_catalog"][0]["stripe_price_id"]
        self.assertTrue(any("Duplicate" in e for e in verify_inventory(data)))

    def test_qa_price_metadata_must_match_checkout_contract(self):
        for bad_metadata in (
            {}, {"product": "fleet", "plan_code": "garage_basic"},
            {"product": "garage", "plan_code": "garage_other"},
            {"product": "garage", "plan_code": None},
        ):
            data = valid_inventory()
            data["prices"][0]["metadata"] = bad_metadata
            self.assertTrue(any("differs" in e for e in verify_inventory(data)))

        data = valid_inventory()
        del data["prices"][0]["metadata"]
        self.assertTrue(any("differs" in e for e in verify_inventory(data)))

    def test_qa_price_must_be_licensed_per_unit(self):
        for patch in (
            {"billing_scheme": "tiered"},
            {"billing_scheme": None},
            {"recurring": {"interval": "month", "interval_count": 1,
                           "usage_type": "metered"}},
        ):
            data = valid_inventory()
            data["prices"][0].update(patch)
            self.assertTrue(any("differs" in e for e in verify_inventory(data)))

    def test_schema_invalid_fails(self):
        self.assertTrue(verify_inventory({"livemode": False}))
        self.assertTrue(verify_inventory([]))


if __name__ == "__main__":
    unittest.main()
