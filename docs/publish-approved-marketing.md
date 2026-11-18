# Publish the approved marketing package

The owner requested deployment of `Flotaryx_aktualizacja_strony_2026-11-18.zip`
on 2026-11-18. Its SHA-256 is
`d505b1a0376c95f35c408bc8f9a58ea1c76e21b8aad39dfc03c41fb96b521a3c`.
This approval covers the already delivered site payload: exactly three changed
HTML pages, 161 files in total and all 97 existing `/app/` files unchanged.
It does not approve a Flutter rebuild, the separate Booking recovery candidate,
database migrations, Auth changes or billing changes.

## Manual publication

1. Merge the reviewed publisher only after `exact-approved-payload` and the
   existing regression checks succeed. Merging does not publish.
2. Open GitHub Actions → **Publish approved marketing package** → **Run workflow**.
3. Select `main`; enter `PUBLISH-MARKETING-d505b1a0` in `confirm_release`.
4. Run the workflow. Do not run **Deploy Flotaryx** for this release: that other
   workflow rebuilds the application.
5. Publication is complete only when `deploy` and the final verification pass.
   Check `https://flotaryx.com/`, `/start/` and `/install/` in a browser.

## What is verified

The committed approval manifest is separately pinned by SHA-256 in the workflow.
The publisher downloads retained artifact `14443664409` from run `44343745692`,
checks the complete previous inventory, reads only the three marketing pages
from immutable commit `deb7643c4bf84251d1de3bc2818cd1ede4194a56`, and checks all
resulting bytes against the delivered package manifest. The outer ZIP wrapper
is not re-created; every published file inside `site/` is identical.

Immediately before publication, unauthenticated HTTPS checks compare all 161
public files and four directory entry URLs against the previous snapshot. A
difference holds publication. After publication, the same checks compare against
the approved new payload; stale CDN responses receive bounded retries. An HTTP
200 alone is never accepted as evidence of correct content.

Only the deployment job has Pages and OIDC write permissions. The preparation
and PR-review jobs cannot deploy. The manual event, main-only check and explicit
release input are mandatory. The `pages` concurrency group is shared with the
existing deployment workflow.

## Rollback and evidence

The full previous site is retained as `marketing-rollback-site` for 30 days in
each publication run. The delivered ZIP also contains the exact original
capture ZIP in `rollback/`. Do not rebuild Flutter to recover this static release.
If verification fails after publication, inspect the retained JSON evidence and
prepare a separately gated deployment of that exact prior site; retain all paths,
including `app/.last_build_id`. This publisher fails closed if re-run after a
successful publication because the old baseline no longer matches the three pages.

`marketing-publication-evidence` records the preflight and final verification.
These results cover static bytes and entry routes; they do not certify hosted
sign-in, database behavior or payment readiness.
