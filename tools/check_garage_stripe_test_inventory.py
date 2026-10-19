#!/usr/bin/env python3
"""Offline validation of SANITIZED Stripe test-mode inventory for Garage QA.

This is configuration checking only: it never calls Stripe, Supabase or the
network and cannot prove an actual seven-day trial / signed webhook E2E.
Do not export keys, customers, raw events or signing secrets to this input.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from urllib.parse import urlsplit

QA_HOST = "fyestmquqvkdebxxbcky.supabase.co"
PRODUCTION_HOST = "wqhymmtiawfwjikdaujo.supabase.co"
WEBHOOK_PATH = "/functions/v1/flotaryx-garage-test-webhook"
REQUIRED_EVENTS = {
    "customer.subscription.created",
    "customer.subscription.updated",
    "customer.subscription.deleted",
    "invoice.paid",
    "invoice.payment_failed",
}
CURRENCIES = {"gbp", "eur", "pln"}
INTERVALS = {"month", "year"}


def verify_inventory(inventory: dict) -> list[str]:
    issues: list[str] = []
    if not isinstance(inventory, dict):
        return ["Expected a JSON object"]
    if inventory.get("livemode") is not False:
        issues.append("Test-mode Stripe account required; never use Live")
    products = inventory.get("products")
    prices = inventory.get("prices")
    endpoints = inventory.get("webhook_endpoints")
    if not all(isinstance(x, list) for x in (products, prices, endpoints)):
        return issues + ["Products, prices and webhook_endpoints must be lists"]

    garage_ids = {
        p.get("id") for p in products
        if isinstance(p, dict) and p.get("active") is True
        and isinstance(p.get("name"), str)
        and "garage" in p["name"].casefold()
        and isinstance(p.get("id"), str)
    }
    if not garage_ids:
        issues.append("No active Garage subscription product in test mode")

    offered: set[tuple[str, str]] = set()
    for price in prices:
        if not isinstance(price, dict) or price.get("active") is not True:
            continue
        if price.get("product") not in garage_ids:
            continue
        currency = price.get("currency")
        interval = price.get("interval")
        amount = price.get("unit_amount")
        if (currency in CURRENCIES and interval in INTERVALS
            and price.get("type") == "recurring"
            and isinstance(price.get("recurring"), dict)
            and price["recurring"].get("interval") == interval
            and price["recurring"].get("interval_count") == 1
            and price.get("livemode") is False
            and type(amount) is int and amount > 0):
            offered.add((currency, interval))
    missing = sorted((currency, interval) for currency in CURRENCIES
                     for interval in INTERVALS if (currency, interval) not in offered)
    if missing:
        issues.append("Missing Garage GBP/EUR/PLN monthly or annual test prices: " +
                      ", ".join(f"{currency}/{interval}" for currency, interval in missing))

    valid_webhooks = 0
    for endpoint in endpoints:
        if not isinstance(endpoint, dict) or endpoint.get("enabled") is not True:
            continue
        url = endpoint.get("url")
        if not isinstance(url, str):
            issues.append("Enabled webhook endpoint without a URL")
            continue
        try:
            parsed = urlsplit(url)
            valid_url = (parsed.scheme == "https" and not parsed.username
                         and not parsed.password and not parsed.query
                         and not parsed.fragment and parsed.port in (None, 443))
        except ValueError:
            valid_url = False
        if not valid_url:
            issues.append("Enabled webhook URL must be credential-free HTTPS")
            continue
        host = parsed.hostname
        if host == PRODUCTION_HOST:
            issues.append("Enabled Stripe test webhook points to production Supabase")
        if host != QA_HOST or parsed.path != WEBHOOK_PATH:
            continue
        events = endpoint.get("enabled_events")
        if not isinstance(events, list):
            issues.append("QA webhook has no explicit event allowlist")
            continue
        if not all(isinstance(event, str) for event in events):
            issues.append("QA webhook event allowlist contains invalid entries")
            continue
        remaining = REQUIRED_EVENTS.difference(events)
        if remaining:
            issues.append("QA webhook missing reconciliation events: " +
                          ", ".join(sorted(remaining)))
            continue
        if "*" in events or set(events) != REQUIRED_EVENTS:
            issues.append("QA webhook event allowlist contains extra or wildcard events")
            continue
        valid_webhooks += 1
    if valid_webhooks != 1:
        issues.append("Expected exactly one eligible enabled, signed Garage QA webhook")
    return issues


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inventory", type=Path,
                        help="Locally prepared sanitized JSON inventory, no secrets")
    args = parser.parse_args()
    try:
        data = json.loads(args.inventory.read_text(encoding="utf-8"))
        errors = verify_inventory(data)
    except (OSError, ValueError) as exc:
        print(f"FAIL: invalid sanitized inventory: {exc}")
        return 1
    for error in errors:
        print(f"BLOCKED: {error}")
    if errors:
        print("NO-GO: test catalog/webhook configuration; no API requests were sent")
        return 1
    print("PASS: sanitized test-mode configuration preflight only")
    print("NOT VERIFIED: hosted Stripe E2E, signing secret, Auth, taxation or legal approval")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
