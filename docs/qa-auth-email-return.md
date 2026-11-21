# QA email return configuration

Production Auth settings must remain unchanged. The QA build uses the explicit
`QA_AUTH_CALLBACK_URL` build define. Missing or unsafe configuration stops the
signup/password-reset request before it reaches Auth; it never substitutes the
production return URL.

Use the exact currently reviewed private preview hostname. The hostname below
is a placeholder, not a deployment target. Set the build-specific path to
`/app/` for the main QA portal or `/booking-recovery-qa/` for the separate
Booking QA portal on private Sites:

```
https://REVIEWED-PREVIEW.chatgpt.site/app/
```

Before testing email confirmation or recovery, verify these exact allowed redirect
URLs in the **QA** Supabase project's Auth URL Configuration:

```
https://REVIEWED-PREVIEW.chatgpt.site/app/
https://REVIEWED-PREVIEW.chatgpt.site/app/?portal=fleet
https://REVIEWED-PREVIEW.chatgpt.site/app/?portal=garage
https://REVIEWED-PREVIEW.chatgpt.site/app/?portal=customer
https://REVIEWED-PREVIEW.chatgpt.site/app/?portal=search
```

For the separate Booking build, verify the equivalent five exact entries
under `/booking-recovery-qa/` as well. Entries for `/app/` do not substitute
for the Booking mount.

Review QA email templates for hardcoded production destinations or `.SiteURL`
links that bypass `.RedirectTo`/the generated confirmation URL. An application
parameter alone cannot guarantee the provider's actual redirect destination.

Hosted Auth configuration and email-template verification have not been completed
by the source tests. Do not treat a successful build as email acceptance. Using a
QA account, verify confirmation returns to the selected panel on the QA origin;
verify reset returns to the recovery form and cannot bypass it into a dashboard.
Verify account switching clears private screens. Do not publish this callback
change to the private preview until the QA provider configuration is verified.

Reference: https://supabase.com/docs/guides/auth/redirect-urls

Run the [read-only QA configuration verifier](qa-auth-policy-verification.md)
with that same reviewed callback before hosted acceptance tests.
