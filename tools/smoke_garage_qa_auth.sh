#!/usr/bin/env bash
# Read-only QA probes. No tokens, API keys, accounts, POSTs or writes.
set -euo pipefail
base="https://fyestmquqvkdebxxbcky.supabase.co/functions/v1"
for fn in flotaryx-garage-test-entitlement flotaryx-garage-test-checkout flotaryx-garage-test-trial-cancel; do
  result=$(curl --silent --show-error --proto "=https" --tlsv1.2 \
    --connect-timeout 10 --max-time 25 --request GET \
    --output /dev/null --write-out "%{http_code}" "${base}/${fn}")
  if [[ "$result" != "401" ]]; then
    echo "FAIL: ${fn} returned ${result} instead of HTTP 401 without credentials" >&2
    exit 1
  fi
  echo "PASS: ${fn} rejects an unauthenticated request (HTTP 401)"
done
echo "Only unauthenticated GETs checked; signed-in access and Stripe E2E not tested."
