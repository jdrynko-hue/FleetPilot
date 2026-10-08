#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is not installed or not on PATH." >&2
  exit 1
fi

flutter create --platforms=android,ios,web --project-name fleetpilot .
flutter pub get

echo
echo "FleetPilot bootstrap complete."
echo "Copy config.example.json to config.json and add your Supabase Project URL + publishable key."
echo "Then run: flutter run -d chrome --dart-define-from-file=config.json"
