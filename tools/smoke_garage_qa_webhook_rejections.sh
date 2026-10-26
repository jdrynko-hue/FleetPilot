#!/usr/bin/env bash
# Hosted QA-only negative webhook signature tests. No real Stripe events or keys.
# Never run against Flotaryx production or another Supabase project.
set -euo pipefail
url="https://fyestmquqvkdebxxbcky.supabase.co/functions/v1/flotaryx-garage-test-webhook"

assert_status() {
  local name="$1" required="$2"
  shift 2
  local actual
  actual="$(curl --silent --show-error --proto '=https' --tlsv1.2 \
    --connect-timeout 10 --max-time 25 --retry 0 \
    --output /dev/null --write-out '%{http_code}' "$@" "$url")"
  if [[ "$actual" != "$required" ]]; then
    printf 'FAIL: %s got HTTP %s; expected HTTP %s\n' "$name" "$actual" "$required" >&2
    exit 1
  fi
  printf 'PASS: %s rejected (HTTP %s)\n' "$name" "$actual"
}
# When configured, GET must be 405. An unconfigured function instead gives
# 503; this gate intentionally fails rather than implying full readiness.
assert_status 'GET' 405 --request GET
# Missing and invalid signatures must fail before invoking any privileged RPC.
assert_status 'POST missing signature' 400 \
  --request POST -H 'Content-Type: application/json' --data-binary '{}'
assert_status 'POST invalid signature' 400 \
  --request POST -H 'Content-Type: application/json' \
  -H 'Stripe-Signature: t=1,v1=0000000000000000000000000000000000000000000000000000000000000000' \
  --data-binary '{"id":"evt_fake_signature_rejected","livemode":false,"type":"invoice.paid"}'

echo 'PASS: QA webhook rejected untrusted requests; no valid signed event sent.'
echo 'NOT TESTED: signing secret matches Stripe, valid signed delivery, paid billing E2E.'
