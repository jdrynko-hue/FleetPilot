# QA email return configuration

Production Auth settings must remain unchanged. The QA build uses the explicit
`QA_AUTH_CALLBACK_URL` build define. Missing or unsafe configuration stops the
signup/password-reset request before it reaches Auth; it never substitutes the
production return URL.

For the current private QA preview, the build define is:

```
https://flotaryx-qa-preview.fairdrake9.chatgpt.site/app/
```

Before testing email confirmation or recovery, verify these exact allowed redirect
URLs in the **QA** Supabase project's Auth URL Configuration:

```
https://flotaryx-qa-preview.fairdrake9.chatgpt.site/app/
https://flotaryx-qa-preview.fairdrake9.chatgpt.site/app/?portal=fleet
https://flotaryx-qa-preview.fairdrake9.chatgpt.site/app/?portal=garage
https://flotaryx-qa-preview.fairdrake9.chatgpt.site/app/?portal=customer
https://flotaryx-qa-preview.fairdrake9.chatgpt.site/app/?portal=search
```

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
