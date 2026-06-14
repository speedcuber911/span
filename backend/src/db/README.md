# src/db — Postgres Access + Migrations

All database interaction: connection pool, query helpers, and migration runner.

Responsibilities:
- Postgres connection pool (plain PostgreSQL — NOT Aurora)
- Row-Level Security (RLS) session variable helpers (`SET app.current_user_id = $1`)
- Typed query wrappers for core tables (users, artifacts, measurements, scores, audit_log, outbox)
- Outbox relay: poll `outbox` table, publish to SQS FIFO, mark as sent (transactional outbox pattern)
- Append-only `audit_log` writer (never UPDATE/DELETE — insert only)
- Migration runner pointing at `../../migrations/`

See `../../migrations/` for SQL migration files.
