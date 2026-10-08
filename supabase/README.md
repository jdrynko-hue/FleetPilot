# Supabase setup

For a **new development project with no real data**, open Supabase → SQL Editor → New query, paste the entire contents of `migrations/001_fleetpilot.sql`, then Run.

The migration is intentionally destructive while the product is still at v0.1: it drops and recreates the FleetPilot tables. Do not run it against a database that contains production data.

After production data exists, create forward-only numbered migrations instead of using this reset migration.

## Authentication

Use Supabase Authentication with Email/Password enabled. If email confirmation is enabled, new users must confirm their address before FleetPilot can open a session.

## Front-end keys

FleetPilot requires the **Project URL** and **anon/publishable key** only. Never put a `service_role` key in Flutter or any client-side application.
