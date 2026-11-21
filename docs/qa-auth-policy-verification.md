# Read-only QA Auth verification

After independently confirming the current private preview origin, run with an
existing authorized Supabase management token (never put it in a command or log):

```sh
python3 scripts/verify_auth_policy.py --environment qa \
  --qa-callback https://REVIEWED-PREVIEW.chatgpt.site/app/
```

Replace the example hostname with the exact reviewed preview hostname. This
reads only QA project `fyestmquqvkdebxxbcky`; `--apply` is rejected before any
request. Production remains the default for existing callers, with its existing
separate opt-in correction behavior. A QA callback cannot be passed to the
production mode.

The verification requires the base callback plus its four supported portal
variants (`fleet`, `garage`, `customer`, `search`) to be explicit entries in the
server's redirect list and a password minimum of at least 12. Wildcards are not
accepted as substitutes for this exact-entry policy. This does not assess every
other existing redirect or prove how the server matches arbitrary patterns.
Missing entries cause failure; no allowlist is broadened and no password policy
is changed. Output contains field names/counts, not complete Auth configuration.

The callback must match the candidate's `QA_AUTH_CALLBACK_URL`. A successful
configuration check is not a successful signup, recovery, email delivery or
hosted browser test. HTTP 401 is an access blocker, not proof of correct or
incorrect callback settings. Do not switch to a production project or use an
unreviewed wildcard to work around failed access.

Offline regression: `python3 -B tests/auth_policy_test.py -v`.
