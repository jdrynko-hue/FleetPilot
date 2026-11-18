# Recovered production baseline — 18 November 2026

The original Pages archive from run 39055761836 expired after one day. Its
successful build log retained the complete verbose tar inventory: 161 files,
including 97 under app/. Recovery used this independent list, not a crawler's
discovered links.

Capture run 44343745692, commit 3014a416f3440afded3fa77b0a0b77299f02591f,
downloaded every listed file from https://flotaryx.com twice. All 161 had identical
bytes and validators in both passes; all were served over HTTPS, including
CNAME and app/.last_build_id. The public Last-Modified date was the pinned
17 October deployment date. Independently, 129 source-backed files matched
the deployed Git objects from fd25fa292127d49d43b49e7feab1f6ed0b237fe8,
accounting for the documented root and /app/ base substitutions.

The captured artifact is 14443664409. Its independently retrieved GitHub ZIP
digest is d9f273d2cb9ac8cce0e7fc7f00b592ffb4da7435f249ac4c2cda52d53cdcf9fc.
This identifies the **new capture archive**, not the expired original archive.
Recovery does not claim to recreate the original ZIP bytes.

## Qualify the downloaded capture

Use the artifact digest and IDs retrieved separately from GitHub. The qualifier
checks the ZIP, the extracted files, the independent original filename list,
capture reports, all hashes and validators, and the deployed Git blob evidence.
It writes a version-2 baseline which explicitly records recovery and the
unavailability of the original archive.

    python3 -B tools/qualify_recovered_baseline.py \
      --capture /absolute/path/to/extracted-capture \
      --source-inventory docs/releases/2026-10-17-production-inventory.json \
      --artifact-archive /absolute/path/to/production-capture.zip \
      --artifact-sha256 d9f273d2cb9ac8cce0e7fc7f00b592ffb4da7435f249ac4c2cda52d53cdcf9fc \
      --capture-run 44343745692 \
      --capture-artifact 14443664409 \
      --output /absolute/path/to/new-baseline-manifest.json

Pass the resulting manifest and its reported digest to
tools/prepare_marketing_release.py with the original captured site/ directory.
Pin marketing source to deb7643c4bf84251d1de3bc2818cd1ede4194a56 (PR221).
The same three-page allowlist, full file inventory and byte-preservation checks
apply to both original and recovered baseline contracts.

## Current Flutter worker

The deployed Flutter 3.47.7 worker intentionally unregisters the old worker and
does not contain a RESOURCES map. The portal guard recognizes only the exact
upstream file hash a131df5ca46154cc4eb79044f7f5a14029c2f8bfccf8cef34e3ec3b5a9f5a88c.
Every byte is retained. Unknown workers without a resource inventory remain
rejected; legacy caching workers still require their complete resource hashes.

The fixture is copied byte for byte from Flutter's BSD-licensed source:
https://github.com/flutter/flutter/blob/3.47.7/packages/flutter_tools/lib/src/web/file_generators/js/flutter_service_worker.js
License: https://github.com/flutter/flutter/blob/3.47.7/LICENSE

## Publication boundary

The capture and preparation workflows do not publish. The package changes only
index.html, start/index.html and install/index.html, preserving the other 158
files, including all 97 app/ files. The captured site is the rollback baseline.

Before an authorized publication, recheck that production has not changed since
capture and bind approval to the prepared package SHA-256. Upload the exact
reviewed site/ directory through a publisher that does not rebuild Flutter.
The existing Deploy Flotaryx workflow rebuilds Flutter and must not be used for
this marketing-only package. Hosted database and payment rollout gates remain
outside this change.

