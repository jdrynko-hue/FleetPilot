# Flotaryx — Smarter Fleet Management

Flotaryx is a multi-company, multilingual fleet management web application built with Flutter and Supabase. It supports vehicle and driver records, daily walkaround checks, issues and defects, repairs and their costs, garages, documents, notifications and CSV exports, with different access for managers and drivers.

## Open the application

- Temporary working URL: https://jdrynko-hue.github.io/FleetPilot/
- Product website: https://jdrynko-hue.github.io/FleetPilot/start/
- Installation guide: https://jdrynko-hue.github.io/FleetPilot/install/
- Purchased product domain: `flotaryx.com` (requires DNS and GitHub Pages custom-domain setup before use)

The web app can be added to the home screen on supported iPhone and Android devices. It is **not** a native App Store or Google Play release.

## Brand and application identity

Customer-facing text, web page names, the app icon and website are branded Flotaryx. Technical identifiers such as the GitHub repository path, Flutter package name, Supabase project identifiers and database/RPC names remain stable to avoid breaking existing integrations. Do **not** rename them during a cosmetic branding change.

## Operational boundaries

- Requires an internet connection.
- No live GPS tracking, telemetry, dispatching, taxi dispatch or tachograph compliance.
- Specialized integrations may be considered in future development; no launch date is guaranteed.
- Email reminders currently have a test-only implementation and require production sender verification, scheduling and re-deployment before general customer use.
- Billing and payment collection are not yet integrated; confirm production readiness before selling subscriptions.

## Deployment

The GitHub Pages workflow is `.github/workflows/deploy.yml`. It currently builds for the repository path `/FleetPilot/`. The purchased custom domain must be configured first; after DNS and HTTPS are confirmed, change the Flutter web build base href and PWA `start_url`/`id`/`scope` to `/`, then add the new origin to the Supabase Auth redirect allowlist.

## Supabase data

The current hosted Supabase project contains development/test records. This rebranding does not drop tables, delete records or run migrations. Testing data may be cleared separately after confirming no live accounts are affected. The existing `supabase/migrations/001_fleetpilot.sql` is a destructive development reset — **do not run it on production data**.

## Launch checklist

Before onboarding paying customers, validate password recovery and invitation links on the custom domain, data access controls, production email delivery, billing, privacy policy, terms, support address, backup/restore and a complete acceptance test with separate companies and user roles.
