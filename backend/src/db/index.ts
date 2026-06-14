/**
 * Project Span — Database access module
 *
 * Thin pg pool wrapper with RLS session-variable support.
 *
 * Usage:
 *   import { pool, query, withUser } from './src/db/index.js';
 *
 *   // Direct query (no RLS — use only from migration/internal contexts):
 *   const { rows } = await query('SELECT now()');
 *
 *   // RLS-scoped query (all PHI access must go through this):
 *   await withUser(userId, async (client) => {
 *     const { rows } = await client.query(
 *       'SELECT * FROM measurements WHERE user_id = $1', [userId]
 *     );
 *   });
 */

import pg from 'pg';

const { Pool } = pg;

// ---------------------------------------------------------------------------
// Pool configuration — reads from environment variables.
// In production these are injected via AWS Secrets Manager / environment.
// ---------------------------------------------------------------------------
export const pool = new Pool({
  host:     process.env.PGHOST     ?? 'localhost',
  port:     Number(process.env.PGPORT ?? '5432'),
  database: process.env.PGDATABASE ?? 'span',
  user:     process.env.PGUSER     ?? 'span_app',
  password: process.env.PGPASSWORD,
  // India-only deployment — one EC2 co-locates app + Postgres, so a small
  // pool is fine to start.  Scale up when Postgres moves to its own box.
  max:      Number(process.env.PGPOOL_MAX ?? '10'),
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 5_000,
  // Enforce SSL in production; skip locally (set PGSSL=false).
  ssl: process.env.PGSSL === 'false'
    ? false
    : { rejectUnauthorized: process.env.NODE_ENV === 'production' },
});

// Surface connection errors immediately rather than silently swallowing them.
pool.on('error', (err) => {
  console.error('[db] idle client error', err);
});

// ---------------------------------------------------------------------------
// query — fire-and-forget helper for non-PHI / migration-role queries.
// For PHI access always use withUser() so RLS is enforced.
// ---------------------------------------------------------------------------
export async function query<T extends pg.QueryResultRow = pg.QueryResultRow>(
  text: string,
  values?: unknown[],
): Promise<pg.QueryResult<T>> {
  const start = Date.now();
  const result = await pool.query<T>(text, values);
  const duration = Date.now() - start;
  if (process.env.PGLOG_SLOW && duration > Number(process.env.PGLOG_SLOW)) {
    console.warn(`[db] slow query (${duration}ms)`, { text: text.slice(0, 120) });
  }
  return result;
}

// ---------------------------------------------------------------------------
// withUser — executes fn inside a transaction with the RLS session variable
// set to the given userId.  ALL PHI reads and writes must go through here.
//
//   • Uses SET LOCAL so the variable is scoped to this transaction only.
//   • Rolls back automatically if fn throws.
//   • The pool client is released in all cases (finally block).
//
// Example:
//   const measurements = await withUser(userId, async (client) => {
//     const { rows } = await client.query(
//       `SELECT * FROM measurements WHERE user_id = $1 ORDER BY date DESC`,
//       [userId],
//     );
//     return rows;
//   });
// ---------------------------------------------------------------------------
export async function withUser<T>(
  userId: string,
  fn: (client: pg.PoolClient) => Promise<T>,
): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // SET LOCAL is transaction-scoped — automatically cleared on COMMIT/ROLLBACK.
    // current_setting('app.current_user_id', true) is the RLS predicate in 0002_rls.sql.
    await client.query('SET LOCAL app.current_user_id = $1', [userId]);
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

// ---------------------------------------------------------------------------
// withTransaction — a transaction without an RLS user (for system/worker ops
// that already run as a privileged role, e.g. outbox relay, audit writes).
// ---------------------------------------------------------------------------
export async function withTransaction<T>(
  fn: (client: pg.PoolClient) => Promise<T>,
): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

// ---------------------------------------------------------------------------
// shutdown — call during SIGTERM to drain the pool gracefully.
// ---------------------------------------------------------------------------
export async function shutdown(): Promise<void> {
  await pool.end();
}
