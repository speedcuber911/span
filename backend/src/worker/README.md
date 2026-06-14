# src/worker — Parse + Analyze Jobs

In-process async worker (runs on the same EC2 as the API) that polls SQS FIFO.

Responsibilities:
- Dequeue parse jobs (artifact_id, user_id) from SQS FIFO queue
- Fetch raw bytes from S3 (ap-south-1)
- Dispatch to `src/llm/` for Document AI OCR + Gemini extraction
- Normalize units, LOINC-canonicalize, deduplicate measurements
- Enqueue analyze job or run inline analysis via `src/analysis/`
- Idempotent: safe to re-run on DLQ redelivery
- Write results back to Postgres; update artifact status
