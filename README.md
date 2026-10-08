# FleetPilot v0.1

FleetPilot is a future-ready, multi-company fleet management MVP built with **Flutter + Supabase**.

The current release is designed to prove the product with a real fleet before adding heavier features such as driver self-service, photo uploads, automated reminders, billing and AI.

## What already works

- Email/password registration and login
- Create a company workspace after first login
- Multi-company membership model
- Roles: Owner / Admin / Manager / Viewer
- Row Level Security (RLS) separating company data
- Dashboard with fleet status, open issues, inspection alerts and repair spend
- Vehicles
  - registration, make, model, year, VIN
  - mileage and operational status
  - current driver
  - MOT/inspection due date
  - service due date/mileage
  - insurance expiry
  - notes and archiving
- Drivers
- Garages / workshops
- Issues / defects with priority and status
- Repairs with garage, linked issue, dates, mileage and cost breakdown
- Vehicle detail screen with issue and repair history
- Automatic driver-assignment history in the database
- Responsive navigation for phone and desktop/web

## Architecture

```text
Flutter client
   |
   |-- Supabase Auth
   |-- Supabase Data API
   |
Supabase PostgreSQL
   |
   |-- companies
   |-- company_members
   |-- drivers
   |-- vehicles
   |-- vehicle_assignments
   |-- garages
   |-- issues
   |-- repairs
   |
   `-- RLS policies
```

Every operational row belongs to a `company_id`. RLS checks the authenticated user's membership before exposing data.

## 1. Prepare Supabase

If the Supabase project contains **no real FleetPilot data yet**, open:

**Supabase → SQL Editor → New query**

Paste the entire contents of:

`supabase/migrations/001_fleetpilot.sql`

Then press **Run**.

> The v0.1 migration is a development reset and drops/recreates the FleetPilot tables. Do not run it after production data exists.

## 2. Get the Supabase client details

In the Supabase dashboard open the project's **Connect** panel and copy:

- Project URL
- Publishable key (`sb_publishable_...`)

Never place a secret/service-role key in this Flutter app.

## 3. Create local config

Copy:

`config.example.json`

to:

`config.json`

Then fill in your own values:

```json
{
  "SUPABASE_URL": "https://YOUR_PROJECT.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_REPLACE_ME"
}
```

`config.json` is ignored by git.

## 4. Generate Flutter platform folders

This source package intentionally does not freeze Android/iOS/web scaffold files to one machine-specific Flutter template.

After installing Flutter, run inside the project folder:

```bash
./tool/bootstrap.sh
```

Or run the equivalent commands manually:

```bash
flutter create --platforms=android,ios,web --project-name fleetpilot .
flutter pub get
```

The project targets Dart 3.9+ and the current Flutter stable generation.

## 5. Run FleetPilot on the web

```bash
flutter run -d chrome --dart-define-from-file=config.json
```

Or on a connected device/simulator:

```bash
flutter devices
flutter run -d DEVICE_ID --dart-define-from-file=config.json
```

## 6. First login

1. Open FleetPilot.
2. Choose **Create an account**.
3. Register with email/password.
4. If Supabase email confirmation is enabled, confirm the email first.
5. Sign in.
6. Create the first company workspace.
7. You become that company's `owner` automatically.

No vehicle, driver or garage seed data is inserted by the project.

## Roles

| Role | Read fleet | Create/edit fleet | Company administration |
|---|---:|---:|---:|
| Owner | Yes | Yes | Yes |
| Admin | Yes | Yes | Yes |
| Manager | Yes | Yes | No |
| Viewer | Yes | No | No |

The UI already respects the main read/write split. RLS is the real security boundary.

## Important security rule

The Flutter app uses only the Supabase **publishable key**. This key is meant for client applications. Data protection comes from authentication + Row Level Security.

Never ship any of these in Flutter:

- `service_role`
- `sb_secret_...`
- database password

## Development notes

The code intentionally keeps dependencies light. The app currently uses only `supabase_flutter` in addition to Flutter itself. That reduces early maintenance and makes the MVP easier to understand.

Before selling FleetPilot to external customers, add at minimum:

- automated tests against a staging Supabase project
- audit log for privileged actions
- invitation flow for team members
- password reset/deep-link configuration
- attachment/photo storage rules
- notification jobs
- privacy policy / terms
- backup and recovery process
- error monitoring
- production migration workflow (no destructive reset scripts)

See `ROADMAP.md` for the planned path toward v1.0.
