# src/worker — Parse → Deterministic Post-Process → Persist

In-process async worker (same EC2 as the API). Long-polls SQS FIFO and runs the
parse pipeline (SPAN_MASTER_PLAN.md §4/§5). Idempotent on `artifact_id`; failures
are not deleted from the queue → SQS redelivers and DLQs after `maxReceiveCount`.

## Files

- **`index.ts`** — `runWorker()`: receive `ingestion.parse.requested` → per job:
  1. `status='parsing'`
  2. call the LLM parse — `parseReport(s3Key, hint)` from `src/llm/parse.js`,
     imported **defensively** (dynamic `import()` in try/catch). If the module is
     missing or throws, the job is marked `failed` and the message is **not
     deleted** (→ retry → DLQ). The boundary type is our `ParseReportFn`.
  3. deterministic post-process (`postprocess.ts`) — *the part we own*
  4. UPSERT `reports` (one per `artifact_id`) + `measurements`
     (`ON CONFLICT (user_id, report_id, parameter, date) DO UPDATE` — idempotent)
  5. `status='extracted'`, or `needs_review` if any low-confidence / outlier /
     unmapped / unit-blocked rows (those also raise `review_tasks`)
  6. write `ingestion.parse.completed` **and** `measurements.committed` outbox
     rows (the latter triggers the analysis layer to recompute trends/scores, §7)
     — all in one RLS transaction
  7. delete the SQS message **only on success**
- **`postprocess.ts`** — pure, testable STAGE-3 logic (§5), reading
  `canonical_parameters` + `unit_rules` from the DB (cached via `loadDictionary`):
  - **3a** `canonicalize` — alias / regex → `canonical_param_id`
  - **3b** `normalizeUnit` — identity / scale / linear conversions; **never**
    auto-converts `nonlinear_blocked` (e.g. Lp(a) mg/dL⇄nmol/L) — keeps raw + flags
  - **3c** `parseRefRange` — `ref_low/high` + sex/age `ref_qualifier`
  - **3e** `deriveFlag` — trust the printed lab flag, else derive from bounds
  - **3f** `outlierGuard` — out-of-plausibility → `value=null` (keeps `value_text`)
  - **3g** `dedupMeasurements` — collapse identical canonical rows, keep best conf
- **`__tests__/postprocess.test.ts`** — vitest: unit normalization (identity /
  ×1000 scale / nonlinear_blocked stays raw+flagged), outlier guard (implausible
  → null but text kept), censored `<200`/`> 24` operator preservation, plus
  ref-range / flag / canonicalize / dedup coverage. **18 tests, all passing.**

## Run

`npm run start:worker` (poll loop) — needs `SQS_QUEUE_URL`, S3/KMS env, PG env.
Without `SQS_QUEUE_URL` the loop idles (local dev). Pair with the ingestion
`runOutboxRelay()` to drain `outbox` → SQS.
