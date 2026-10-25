# Isolated native PG17 acceptance only

This branch tree intentionally contains only one synthetic test job and its dependencies.
It is not the application release candidate and must never be merged into main.
No hosted Supabase or production inputs/secrets are used.
No native PASS is claimed until the actual job completes and observed lock edges are reviewed.
