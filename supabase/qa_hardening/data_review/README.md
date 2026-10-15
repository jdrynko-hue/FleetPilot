# Guarded fictional QA document metadata repair

The user confirmed that hosted QA contains their own fictional accounts and
authorized necessary QA work on 15 October 2026. The approved scope does not
include production, paid services or Stripe Live.

The CLI-generated SQL is staged here, outside automatic migrations. It repairs
only invalid-prefix PDF metadata when **both Storage buckets and objects are
empty**. It does not upload, move or invent any actual file. Correctly scoped
paths remain unchanged. Every changed original path is saved in a private,
RLS-enabled table with no API-role grants. The transaction uses table locks,
short timeouts and post-verification; drift, existing backup schemas, unsupported
types, nonempty Storage and blocked writes abort all changes.

Original paths can be restored with a separately reviewed, guarded update while
no new path constraint has been installed. After hardening, restoring an invalid
path would correctly fail its CHECK constraint; do not weaken security to restore
obsolete fixture metadata. The private archive preserves the original values for
review, rather than promising an unconditional rollback after later migrations.

The disposable test covers successful normalization/private backup, preservation
of valid paths, a guarded restore, blocked replay, nonempty buckets/objects,
unsupported MIME, foreign vehicle, pre-existing review schema, no-op refusal and
atomic rollback when an existing trigger rejects the metadata update. It never
connects to hosted QA or production.
