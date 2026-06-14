# src/ingestion — Presign · Dedup · Idempotency · Transactional Outbox

The front door for all PHI (SPAN_MASTER_PLAN.md §4). Dumb, durable, idempotent:
authenticate, consent-gate, presign a direct device→S3 PUT (bytes never transit
the app server), dedup by content hash, and hand off exactly one parse job per
*new* artifact via the transactional outbox → SQS FIFO.

## Files

- **`types.ts`** — the cross-component wire contracts (single source of truth):
  - HTTP shapes: `IngestionIntentRequest/Response`, `IngestionJobView`
  - queue messages: `ParseRequestedMessage`, `ParseCompletedMessage`,
    `MeasurementsCommittedMessage` (all carry `schema_version`, region pins)
  - **`ExtractedReport` / `ExtractedRow`** — the contract with `src/llm`
    (`parseReport(s3Key, hint) → ExtractedReport`). The LLM transcribes only.
- **`routes.ts`** — Fastify plugin (`ingestionRoutes`) the API registers:
  - `POST /v1/ingestion/intents` — batch; consent-gate (409 if no active
    `ingestion` consent); dedup on `UNIQUE(user_id, content_sha256)` → verdict
    `new|duplicate`; for `new`, create `ingestion_artifacts` +
    `ingestion_jobs(status='intent_created')` + a presigned SSE-KMS PUT URL
    (key `u/{user_id}/raw/{artifact_id}.{ext}`, TTL 5 min).
  - `POST /v1/ingestion/:jobId/complete` — HEAD the object (exists/size), then
    flip `status='enqueued'` **and** write the `ingestion.parse.requested`
    outbox row **in one transaction** (transactional outbox). Idempotent.
  - `GET /v1/ingestion/jobs` (+ `?status=`) and `GET /v1/ingestion/jobs/:id`
    for the progress UX. All RLS-scoped via `withUser`. Bodies validated with zod.
  - Auth + consent are injectable (`getUserId`, `hasConsent`) so the API /
    compliance agents own those; defaults read `req.user` + the `consents` table.
- **`storage.ts`** — S3 helpers: `presignPutUrl` (SSE-KMS headers signed into the
  URL), `headObject`, `getObjectStream`, `rawKey`.
- **`outboxRelay.ts`** — `runOutboxRelay()` polls `outbox` for unpublished rows
  (`FOR UPDATE SKIP LOCKED`), sends to SQS FIFO
  (`MessageGroupId=user_id`, `MessageDeduplicationId=artifact_id:topic`), marks
  them published in the same transaction. The only producer-side SQS caller.
- **`config.ts`** — env-derived config (India-pinned: ap-south-1 / asia-south1);
  `loadSharedConfig()` overlays the API agent's `../config.js` if present.

## FSM + outbox flow

```
intent_created ──(client PUTs to S3)──▶  /complete: HEAD ok
      │                                        │  (one txn)
      │                                        ▼
      └────────────────────────────▶  status=enqueued + outbox['ingestion.parse.requested']
                                               │
                              outboxRelay ─────┘──▶ SQS FIFO (group=user_id, dedup=artifact_id)
                                                          │
                                                   WORKER (src/worker)
        parsing ──▶ extracted | needs_review   (or failed → DLQ via redelivery)
```

Three idempotency layers: client `idempotency_key` (per batch), content dedup
`UNIQUE(user_id, content_sha256)`, queue dedup `MessageDeduplicationId`.
