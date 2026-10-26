# Flotaryx — UK pilot legal readiness review (18 October 2026)

**Status: review required; not legal advice and not authorization to sell.**

## Verified facts from this repository

- The English Terms page at `web/legal/en/terms/index.html` is written for business customers and refers to a standard **30-day** introductory trial, unless a different trial is displayed. This may be the Fleet default; it is **not evidence** that the Garage seven-day trial is covered for all flows.
- The Garage subscription design in the current Draft stack uses a **seven-day** trial and fixed-price workshop subscription without booking commission. Paid Garage Checkout is not enabled on hosted QA or production.
- The Booking product accepts requests from private vehicle owners as well as Fleet users. The existing B2B terms should not automatically be assumed to cover an individual consumer's use of Booking.
- Twelve localized Terms and twelve localized Privacy documents currently exist in source. A CI check now requires all 24 published documents, titles and support contact. Presence does not confirm accuracy or completeness.
- The Privacy Notice addresses vehicle/driver/workspace and subscription data, but the actual Garage customer booking model, sharing with garages, notifications, deletion periods and processor/controller roles require review against the deployed data flows.

## No-go items before inviting paying users

- [ ] **Legal owner approval:** confirm the contracting entity, contact details and the distinction between Fleet business subscriptions, Garage business subscriptions and private Booking customer accounts.
- [ ] **Trial disclosures:** explicitly reconcile 30-day Fleet default with seven-day Garage offer. Verify country-specific localized checkout copy and confirm the first billing date, amount, cancellation timing and renewal terms before collecting payment details.
- [ ] **Private customer Booking terms:** define whether Booking is an introduction/request service, when a booking is confirmed by a garage, who provides repairs, cancellations, dispute handling and liability allocation. Do not describe a submitted request as a confirmed appointment.
- [ ] **Privacy roles and sharing:** verify what private vehicle owner data is sent to workshops or fleet managers, the lawful basis, transparency at request submission, data retention, incident contacts, user request procedure and subprocessors.
- [ ] **UK VAT/tax and geographic scope:** separately review the UK-first pricing, invoices and whether EU/PL business or consumer sales require local VAT/OSS duties. Do not activate Stripe Live before tax sign-off.
- [ ] **Localization review:** review all 12 translated Terms and Privacy documents for consistency with the approved UK language text. A successful static CI scan is not a legal opinion.
- [ ] **Consent and audit:** establish how effective legal versions are accepted or acknowledged and how revisions are communicated, where legally required.
- [ ] **Contact and support:** confirm `support@flotaryx.com` is an actively monitored channel and that refund / privacy requests can be processed before any live paid pilot.

## Safe acceptance order

1. Finish security and hosted QA tests without real identities or Stripe Live.
2. Obtain specific approval of the business Garage trial and consumer Booking disclosures; keep public marketing truthful about pending features.
3. Publish approved localized legal wording through a separately reviewed PR. Preserve version history and effective dates.
4. Check acceptance controls in the actual app, then authorize only the intended pilot geography and services.

Until sign-off, mark the **paid UK pilot as NO-GO**. No legal page text or customer records were changed in this review.
