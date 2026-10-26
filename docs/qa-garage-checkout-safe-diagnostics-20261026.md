# Garage Checkout safe stage diagnostics

Hosted QA Checkout returned an opaque 503 before a durable trial reservation.
Two reconciled attempts left no trial claim or Checkout Session in the isolated
Sandbox. Owner/catalog resolution and trial reservation succeed as service_role
in a transaction that was rolled back. This does not prove that the deployed
Stripe key is correct or identify the upstream failure.

Add an optional diagnostic sink receiving only a compile-time union of fixed
stage names. The QA Edge entrypoint logs the prefix `garage_checkout_failure`
and that stage. There are no raw errors, IDs, keys, tokens, URLs, or request
payloads in diagnostic output. Clients continue receiving the same opaque error.
Diagnostic sink failure cannot change the fail-closed response. Price and customer
reads are sequential so an operator can identify the failing read unambiguously.

Validation: 274 Garage backend tests passed, including five new diagnostic tests;
strict TypeScript compilation passed. Source and packaged Checkout modules match.
No hosted deployment is included in this Draft PR. QA prices remain inactive;
the isolated Stripe webhook remains disabled. Production and Stripe Live unchanged.

After explicitly authorized QA-only deployment, activate only the reviewed GBP
monthly price for one reconciled attempt, inspect the fixed stage, and disable
the catalog again if preparation fails. Do not retry an uncertain attempt without
checking the durable ledger and Sandbox Checkout Sessions first.
