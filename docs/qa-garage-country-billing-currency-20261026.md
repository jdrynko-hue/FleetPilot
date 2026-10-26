# Garage country-based subscription currency

The workshop's stored business country selects the server-side catalog price:
UK (GB) GBP; Poland (PL) PLN; every other EU member EUR. This includes Czechia,
Denmark, Hungary, Romania and Sweden, whose domestic currencies are not EUR.
This is the requested commercial billing policy, not a claim about legal tender.
Countries outside UK/EU continue failing closed. Browser IP, language and payment
card location must not override the workshop currency.

Garage onboarding now includes UK and all 27 EU members using a Garage-specific
market map. Fleet's separately deployed market allowlist is unchanged. Country
labels and editable time zone suggestions cover the five additional countries.
The QA catalog resolver and bundled schema share the complete EU list. The
incremental QA-only migration replaces only the resolver and retains its grants;
it neither edits workspaces nor activates catalog prices.

Stripe Checkout creation explicitly sets `adaptive_pricing.enabled=false`,
overriding Dashboard currency-localization defaults. The existing GBP trial
session had offered USD based on the browser environment despite a GBP catalog
price. Selecting GBP showed seven free days followed by the correct test GBP
amount. No trial was submitted. PLN did not appear because that workshop is GB;
each country receives its own catalog price rather than a currency picker.

Validation: 277 Garage backend tests and strict TypeScript passed locally.
Added Flutter market coverage for UK/all EU members and disposable SQL coverage
for all 28 countries plus country/currency mismatch rejection. Flutter/database
integration checks run in CI; those runtimes are unavailable locally.

Draft source only: no deployment, migration execution, production or Live
change. Existing Checkout Sessions retain their original parameters. Do not
reuse an existing idempotency attempt with changed parameters: reconcile/expire
the original session through the reviewed operator path before any new attempt.
The real QA owner already has one reserved open test session, with no started
trial or subscription. Use disposable fixtures to test other country mappings.
