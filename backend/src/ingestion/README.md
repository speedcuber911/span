# src/ingestion — S3 Presign + Deduplication

Handles the upload side of artifact ingestion (PDFs, photos, lab emails).

Responsibilities:
- Generate S3 presigned PUT URLs (ap-south-1 bucket, SSE-KMS) for direct device-to-S3 upload
- Enforce region residency: bucket must be ap-south-1; key prefix includes user_id + region='in'
- Artifact deduplication: hash-based dedup before writing to `artifacts` table
- Write artifact record + outbox entry in a single Postgres transaction
- S3 event → SQS enqueue path (via Lambda glue or direct worker poll — see infra/)
- Later: Gmail OAuth fetch integration
