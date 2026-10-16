# Read-only QA public-client smoke test

`tools/qa_public_api_smoke.py` checks the fixed QA API using a publishable key
and no user session. It uses GET requests only: Auth health, the public workshop
directory and explicit privilege denials for private booking reads. It does not
create accounts, send email, submit bookings, apply migrations or deploy.

Keep the local JSON configuration outside the repository, with only `api` and
`anon` fields. The API must match the fixed QA origin in the script. Only modern
`sb_publishable_...` keys are accepted; production, alternate origins, legacy
JWT keys, secrets, passwords, sessions and extra configuration fields are refused.
Do not pass keys in command-line arguments or commit runtime configuration.

Run privately:

```sh
python tools/qa_public_api_smoke.py --config /private/path/qa-client.json
```

The CLI prints check labels only. Failure messages omit response bodies and
exception details. Redirects are refused so an API key cannot be forwarded to
another origin. A missing RPC/schema-cache entry, invalid key, server error or
successful empty private-table response does not count as a privilege denial.

Run offline guard tests without any credentials:

```sh
python -m unittest discover -s tools -p test_qa_public_api_smoke.py -v
```

The dedicated CI workflow runs these offline tests only. It never contacts
hosted QA or uploads runtime results. Keep hosted audit findings and credentials
private. A successful public-client smoke test does not establish authenticated
role/tenant isolation, session handling, Storage access, phone usability or
deployment readiness; those require separate acceptance evidence.
