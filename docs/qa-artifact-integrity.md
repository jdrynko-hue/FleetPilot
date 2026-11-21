# Offline QA artifact inventory

`tools/qa_artifact_integrity.py` checks the **whole extracted directory**,
including hidden files and every portal. It rejects missing, changed and
unexpected files, symlinks, special files, malformed paths and duplicate JSON
keys. No API, credentials, database changes or deployment are involved.

Create an inventory only after finishing an artifact in a separate candidate
directory. The directory must not already contain `qa-release-integrity.json`.
The tool refuses to silently replace even an invalid or stale manifest.

```sh
python3 tools/qa_artifact_integrity.py create --root /private/candidate
python3 tools/qa_artifact_integrity.py verify --root /private/candidate \
  --manifest-sha256 <independently-retained-manifest-sha256>
```

Retain the returned digest independently with the build/review record. Verify
again after downloading or extracting the delivered artifact, using that saved
digest. Recomputing a digest from an untrusted delivered manifest defeats the
external comparison. Verification is read-only and exits nonzero on drift.
Do not regenerate a manifest to conceal differences.

Schema 2 explicitly records `deployment_authorized: false` and
`source_identity_verified: false`. Optional `--declared-source-commit` and
`--declared-source-tree` must be supplied together; these remain **claims**, even
when checksums pass. A mixed artifact must not claim one source commit for all
its portals. A legacy schema-1 manifest is rejected, not silently upgraded.
The manifest itself is the sole excluded file, pinned by the external digest.

The full-regression CI build records its actual checked-out commit/tree (which
may be the PR merge commit), Flutter toolchain, resolved dependency lockfile and
build workflow. These records travel inside the checksummed artifact. The upload
includes hidden build files, so `.last_build_id` cannot silently disappear.
Build inputs contain a placeholder publishable key: this CI artifact is a
compile check, not a ready-to-deploy connected environment.

For an existing private preview, preserve the original archive and manifest,
compare all bytes and document any intentional portal/base-path transformation.
Prepare the new inventory in a separate candidate only after reviewing those
differences. Checksums alone do not establish source/build equivalence, backend
versions, migrations, Auth callback correctness, access controls or deployment
approval. Complete those qualifications and retain a verified rollback before
any publication. Never commit private inventories or recovered source to the
public repository.

Offline regression suite:

```sh
python3 -B tests/qa_artifact_integrity_test.py -v
```
