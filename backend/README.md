# span-backend

TypeScript/Node backend for Project Span. Runs as two co-located processes on a single EC2
instance in ap-south-1 (Mumbai):

1. **`/v1` API** — Fastify HTTP server. Handles auth (Sign in with Apple), consent gating,
   Postgres RLS session injection, artifact presign, measurement/score reads, voice session
   handoff, and data export/delete.

2. **Parse + Analyze Worker** — in-process SQS FIFO consumer. Dequeues parse jobs, fetches
   raw artifacts from S3, calls Vertex AI (Document AI OCR + Gemini extraction) in
   `asia-south1`, normalizes and deduplicates measurements, runs the scoring engine, and
   writes results back to Postgres.

## Stack

| Concern              | Choice                                                     |
|----------------------|------------------------------------------------------------|
| Language             | TypeScript (ESM), Node >= 20                               |
| HTTP framework       | Fastify (or NestJS — TBD)                                  |
| Database             | Plain PostgreSQL with Row-Level Security — NOT Aurora       |
| Async queue          | AWS SQS FIFO + DLQ (pay-per-message, ~$0 at rest)          |
| Object storage       | AWS S3 ap-south-1, SSE-KMS                                 |
| Parse inference      | Vertex AI asia-south1: Google Document AI + Gemini         |
| Voice                | Sarvam AI (all-in-India STT/LLM/TTS)                       |
| Region               | ap-south-1 only — India-first product; DPDP residency      |

**HARD RULE:** India PHI may only touch `ap-south-1` / Vertex `asia-south1`.
Claude / Anthropic APIs are excluded from the India path (cross-region).

## Directory layout

```
backend/
  src/
    api/          HTTP route handlers, auth + consent middleware
    worker/       SQS consumer — parse + analyze job loop
    db/           Postgres pool, RLS helpers, outbox relay, migration runner
    analysis/     Scoring engine: PhenoAge, CKD-EPI, FIB-4, TyG, NAFLD-FS, etc.
    ingestion/    S3 presign, artifact dedup, outbox write
    llm/          Vertex Gemini + Document AI clients (asia-south1)
    voice/        Sarvam session management + RAG context injection
    compliance/   Consent, export/delete pipeline, audit_log, residency assertions
  migrations/     SQL migration files (run via `npm run migrate`)
  .env.example    All required env vars with placeholder values
  package.json    Scripts: dev / build / test / migrate (deps not installed yet)
```

## Getting started

```bash
cp .env.example .env
# Fill in real values — especially DATABASE_URL, AWS_*, VERTEX_*, SARVAM_API_KEY

npm install          # installs deps (not done yet — skeleton only)
npm run migrate      # runs pending SQL migrations
npm run dev          # starts API + worker in watch mode
```

## Key design invariants

- Every PHI write: single Postgres transaction that includes an outbox row
- Outbox relay: background loop reads outbox, publishes to SQS FIFO, marks sent
- RLS: `SET app.current_user_id = $1` before every query; policies enforce isolation
- Residency assertion: every PHI read/write calls `assertRegion(user, 'in')`
- Audit log: append-only — never UPDATE/DELETE rows, only INSERT
- Worker idempotency: DLQ redelivery is safe; artifact status is a state machine

See `SPAN_MASTER_PLAN.md` (root) for the full architecture, medical formulas, and
compliance requirements.
