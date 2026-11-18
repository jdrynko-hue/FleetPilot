# Prepare a marketing update while preserving the deployed portal

`tools/prepare_marketing_release.py` prepares a reviewable folder containing the
complete site. It replaces exactly `index.html`, `start/index.html` and
`install/index.html` from one pinned Git commit. Every other file, including all
compiled `/app/` files, service worker, legal pages, branding and `CNAME`, must
retain its original path and bytes.

The command is offline. It does not build Flutter, crawl the website, download a
QA application, publish to GitHub Pages, change an account, or grant approval.
The existing `Deploy Flotaryx` workflow rebuilds the application and is therefore
not the publication path for this prepared folder.

## Required baseline

Supply a complete retained artifact of the currently deployed production site,
its independently retained file inventory and the trusted SHA-256 of that
inventory. Record the original archive checksum, successful deployment run,
artifact ID and deployed source commit. Verify those facts against the actual
deployment before using this command. Keep the original archive for rollback.

A new checksum made from a partial download does not prove completeness. A
manifest created after losing files cannot qualify that partial download. A
compiled QA artifact is not a production baseline. The tool checks the supplied
evidence consistently; it does not authenticate a caller-authored provenance
claim or independently query GitHub.

The JSON contract is:

```json
{
  "version": 1,
  "kind": "flotaryx-production-baseline",
  "origin": "https://flotaryx.com",
  "repository": "jdrynko-hue/FleetPilot",
  "provenance": {
    "deployment_status": "success",
    "source_commit": "<full deployed 40-character commit SHA>",
    "deployment_run_id": 123,
    "artifact_id": 456,
    "archive_sha256": "<trusted original archive SHA-256>"
  },
  "files": {
    "index.html": {"sha256": "<file SHA-256>", "size_bytes": 1234},
    "app/index.html": {"sha256": "<file SHA-256>", "size_bytes": 5678}
  }
}
```

The displayed entries and numbers are illustrative. `files` must enumerate
**every** regular file in the complete extracted site, including dotfiles and
all app assets. The command refuses a missing or extra file, changed hash or
size, symlink, unsafe path, duplicate JSON key, missing bootstrap entrypoint or
inconsistent retained service worker resource. The manifest's own digest must
match the separately supplied trusted value.

## Prepare

Use the exact reviewed source commit containing the desired website changes.
The command reads Git objects, so uncommitted edits are not included.

```bash
python3 tools/prepare_marketing_release.py \
  --baseline /absolute/path/to/retained-production-site \
  --baseline-manifest /absolute/path/to/production-manifest.json \
  --baseline-manifest-sha256 TRUSTED_MANIFEST_SHA256 \
  --source-repo /absolute/path/to/FleetPilot \
  --source-commit REVIEWED_FULL_COMMIT_SHA \
  --output /absolute/path/to/new-review-folder
```

The output must be new and outside both the baseline and source directories.
Preparation happens in a temporary folder. Only a completely validated candidate
becomes visible at the requested output path. Failure does not leave a partially
prepared publication folder or overwrite an existing result.

Successful output contains:

- `site/`: complete proposed GitHub Pages content.
- `baseline-manifest.json`: unchanged input evidence for the retained rollback.
- `release-manifest.json`: exact proposed file inventory and SHA-256 values.
- `review.json`: source commit, baseline provenance, changed paths, protected
  file counts and the assertion that the complete app inventory is identical.

It also checks statically discoverable links and assets in the three replaced
HTML pages. JavaScript-generated navigation and actual Auth behaviour still need
their existing browser acceptance checks. Missing new marketing assets cause a
hold; expanding the three-file allowlist requires a separate reviewed change.

## Publication remains separate

Review the exact `site/` folder, its source commit, current CI and rollback
artifact. Resolve all applicable release gates in `production-release-runbook.md`
and record the owner's explicit publication approval. A dedicated approved
publisher must upload the reviewed folder without rebuilding or assembling a
different app. This PR intentionally provides no deploy workflow or Pages write
permission.

After an authorized publication, verify `/`, `/start/`, `/install/`, the language
handoff and `/app/`, and compare the protected app hashes with the retained
baseline. An HTTP 200 alone does not prove Auth or payment readiness.

If the complete production baseline cannot be obtained, preparation remains
blocked. The alternative is to qualify a complete new application release with
its own checks and approval; it is not a marketing-only update.

## Automated evidence

`python3 -B tests/marketing_release_test.py -v` uses synthetic offline artifacts
to verify byte preservation, immutable source selection, required provenance,
missing/changed/extra files, symlinks, path traversal, service worker integrity,
missing links, duplicate manifest keys and safe output handling. These tests
qualify the preparation code, not any production artifact.
