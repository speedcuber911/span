# src/compliance — Consent, Export/Delete, Audit

Privacy-by-design spine. Covers both GDPR (future EU) and India DPDP (current).

Responsibilities:
- Consent management: record active/withdrawn consent per user; consent gate used in src/api/
- Data export pipeline: generate full NDJSON export of all user PHI rows (DPDP / GDPR Article 20)
- Data deletion pipeline: hard-delete PHI from Postgres + S3 purge + KMS key rotation (DPDP / GDPR Article 17)
- Append-only audit_log writer: every PHI access/mutation records user_id, action, timestamp, actor
- Region residency assertion helpers: `assertRegion(user, 'in')` — called on every PHI read/write
- Retention policy enforcement (future): auto-delete artifacts older than configured window

Deletion is irreversible. Export/delete requests must be queued and confirmed — never inline.
