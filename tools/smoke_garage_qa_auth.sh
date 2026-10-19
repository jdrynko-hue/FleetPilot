#!/usr/bin/env bash
# Read-only hosted QA checks: no valid credentials, accounts or requests that mutate state.
set -euo pipefail
base="https://fyestmquqvkdebxxbcky.supabase.co/functions/v1"
for fn in flotaryx-garage-test-entitlement flotaryx-garage-test-checkout flotaryx-garage-test-trial-cancel; do
  # A missing credential AND a forged bearer must fail at the Supabase gateway.
  for auth_case in missing fake-bearer; do
    options=()
    if [[ "$auth_case" == "fake-bearer" ]]; then
      options=(-H "Authorization: Bearer invalid-qa-smoke-jwt")
    fi
    status=$(curl --silent --show-error --proto "=https" --tlsv1.2 \
      --connect-timeout 10 --max-time 25 --request GET \
      --output /dev/null --write-out "%{http_code}" \
      "${options[@]}" "${base}/${fn}")
    if [[ "$status" != "401" ]]; then
      printf "FAIL: %s accepted %s with HTTP %s (required: 401)\n" "$fn" "$auth_case" "$status" >&2
      exit 1
    fi
    printf "PASS: %s rejects %s with HTTP 401\n" "$fn" "$auth_case"
  done
done
echo "Only unauthenticated read-only GETs were sent; no hosted Auth or Stripe E2E."
