/**
 * Project Span — Data-subject rights engine (GDPR Art. 15/17/20 + India DPDP +
 * App Store 5.1.1(v)).  One pipeline serves all three regimes (SPAN_MASTER_PLAN §9).
 *
 *   assembleExport(userId)  — synchronously gather a machine-readable JSON archive
 *                             of every caller-owned row across all PHI tables.
 *   deleteAccount(userId)   — status='deletion_pending' → cascade-delete PHI via
 *                             ON DELETE CASCADE from users → keep append-only
 *                             audit_log → write a phi.delete audit → status='deleted'.
 *
 * Both run server-side, in-region only.  No PHI ever leaves ap-south-1.
 *
 * NOTE (MVP scope): the export is assembled and returned inline as JSON.  In
 * production this archive (JSON + the original PDFs from S3) is written to a
 * short-lived presigned S3 object and the caller is handed the presigned URL —
 * see the S3 hand-off marker below.  Raw S3 object purge on delete is likewise
 * marked; the row cascade is implemented here.
 */

import type pg from 'pg';

import { withUser, withTransaction, query } from '../db/index.js';
import { RESIDENCY } from '../config.js';

// ---------------------------------------------------------------------------
// The full set of user-owned PHI tables.  Each is exported under its own key.
// Order is not important for export; for delete we rely on ON DELETE CASCADE
// from users(id), so deleting the users row removes all of these.
//
// `column` is the user-scoping FK (almost always user_id).  `transcripts` and
// `voice_sessions` both carry user_id, so they are exported directly even though
// transcripts also cascades from voice_sessions.
// ---------------------------------------------------------------------------
const PHI_TABLES: ReadonlyArray<{ table: string; userColumn: string; orderBy: string }> = [
  { table: 'profiles', userColumn: 'user_id', orderBy: 'updated_at' },
  { table: 'consents', userColumn: 'user_id', orderBy: 'granted_at' },
  { table: 'ingestion_artifacts', userColumn: 'user_id', orderBy: 'uploaded_at' },
  { table: 'ingestion_jobs', userColumn: 'user_id', orderBy: 'created_at' },
  { table: 'gmail_sync_state', userColumn: 'user_id', orderBy: 'user_id' },
  { table: 'review_tasks', userColumn: 'user_id', orderBy: 'created_at' },
  { table: 'reports', userColumn: 'user_id', orderBy: 'report_date' },
  { table: 'measurements', userColumn: 'user_id', orderBy: 'date' },
  { table: 'parameter_catalog', userColumn: 'user_id', orderBy: 'parameter' },
  { table: 'parameter_stats', userColumn: 'user_id', orderBy: 'computed_at' },
  { table: 'scores', userColumn: 'user_id', orderBy: 'computed_at' },
  { table: 'analysis_results', userColumn: 'user_id', orderBy: 'computed_at' },
  { table: 'qol_entries', userColumn: 'user_id', orderBy: 'recorded_at' },
  { table: 'healthkit_samples', userColumn: 'user_id', orderBy: 'start_at' },
  { table: 'healthkit_anchors', userColumn: 'user_id', orderBy: 'user_id' },
  { table: 'voice_sessions', userColumn: 'user_id', orderBy: 'started_at' },
  { table: 'transcripts', userColumn: 'user_id', orderBy: 'created_at' },
  { table: 'prep_reports', userColumn: 'user_id', orderBy: 'created_at' },
];

export interface ExportArchive {
  schema: 'span.export.v1';
  generated_at: string;
  region: string;
  user: Record<string, unknown> | null;
  tables: Record<string, unknown[]>;
  /** Where the original uploaded PDFs/photos would be linked in the prod archive. */
  raw_files_note: string;
  counts: Record<string, number>;
}

/**
 * Assemble a complete export archive for one user.  All reads run under the RLS
 * session variable (withUser) so a bug here still cannot read another user's rows.
 */
export async function assembleExport(userId: string): Promise<ExportArchive> {
  return withUser(userId, async (client: pg.PoolClient) => {
    // users row (RLS: the policy on users keys on id, so this returns only self).
    const userRes = await client.query(
      `SELECT * FROM users WHERE id = current_setting('app.current_user_id', true)::uuid`,
    );
    const userRow = userRes.rows[0] ?? null;

    const tables: Record<string, unknown[]> = {};
    const counts: Record<string, number> = {};

    for (const { table, userColumn, orderBy } of PHI_TABLES) {
      // Table + column names come from a fixed allowlist above (never user input),
      // so interpolation here is safe; the user filter is parameterised via RLS.
      const res = await client.query(
        `SELECT * FROM ${table}
          WHERE ${userColumn} = current_setting('app.current_user_id', true)::uuid
          ORDER BY ${orderBy}`,
      );
      tables[table] = res.rows;
      counts[table] = res.rowCount ?? res.rows.length;
    }

    return {
      schema: 'span.export.v1' as const,
      generated_at: new Date().toISOString(),
      region: RESIDENCY.region,
      user: userRow,
      tables,
      // S3 HAND-OFF (prod): list presigned GET URLs for every
      // s3://span-phi-in/u/{userId}/raw/* object here, generated with a short TTL
      // and bound to the region CMK; in MVP we only surface the DB-side metadata
      // (ingestion_artifacts.storage_key) which is already included above.
      raw_files_note:
        'Original uploaded PDFs/photos live in S3 (ap-south-1, SSE-KMS); ' +
        'in production this archive links short-lived presigned GET URLs per artifact.',
      counts,
    };
  });
}

export interface DeleteResult {
  user_id: string;
  status: 'deleted';
  deleted_at: string;
  /** Row counts removed per table (for the audit detail / caller receipt). */
  cascade_counts: Record<string, number>;
}

/**
 * Execute the irreversible account-deletion pipeline.
 *
 *   1. status='deletion_pending' (marks intent; idempotent re-entry safe).
 *   2. Snapshot per-table counts (for the audit receipt) under RLS.
 *   3. DELETE FROM users WHERE id = userId  → ON DELETE CASCADE removes every PHI
 *      row in every child table.  Runs as the privileged role (withTransaction):
 *      the app role intentionally lacks DELETE on data tables, and deletion is the
 *      one pipeline allowed to run as owner (§9).  The append-only audit_log has
 *      no FK to users and is NOT cascaded — it is retained as proof.
 *   4. Write the phi.delete audit row.
 *
 * Because the users row is gone, there is no surviving status='deleted' row in
 * `users`; the deletion proof lives in audit_log (which is what GDPR/DPDP require:
 * a record THAT erasure happened, holding no PHI).
 */
export async function deleteAccount(userId: string): Promise<DeleteResult> {
  // 1. Mark intent (privileged update; survives even if step 3 is retried).
  await query(`UPDATE users SET status = 'deletion_pending', updated_at = now() WHERE id = $1`, [
    userId,
  ]);

  // 2. Count rows per table for the receipt (RLS-scoped read).
  const cascade_counts: Record<string, number> = {};
  await withUser(userId, async (client) => {
    for (const { table, userColumn } of PHI_TABLES) {
      const res = await client.query(
        `SELECT count(*)::int AS n FROM ${table}
          WHERE ${userColumn} = current_setting('app.current_user_id', true)::uuid`,
      );
      cascade_counts[table] = (res.rows[0] as { n: number } | undefined)?.n ?? 0;
    }
  });

  // 3 + 4. Cascade-delete + write deletion proof in ONE transaction.
  const deletedAt = new Date().toISOString();
  await withTransaction(async (client) => {
    // ON DELETE CASCADE from users(id) wipes every child PHI table.
    // refresh_tokens also cascades (FK → users ON DELETE CASCADE, migration 0004).
    await client.query(`DELETE FROM users WHERE id = $1`, [userId]);

    // S3 PURGE (prod): enqueue / synchronously delete every
    // s3://span-phi-in/u/{userId}/* object (raw, pages, derived) and let Object
    // Lock / lifecycle finalize.  MVP deletes the DB rows; the S3 purge job is the
    // documented next hop (§9 "delete region S3 objects").

    // Append-only deletion proof.  audit_log is NOT cascaded (no FK to users) and
    // the app role cannot UPDATE/DELETE it (migration 0002) — so this is durable.
    await client.query(
      `INSERT INTO audit_log (user_id, actor, action, entity, entity_id, region, meta)
       VALUES ($1, $2, 'phi.delete', 'users', $1, $3, $4)`,
      [
        userId,
        `user:${userId}`,
        RESIDENCY.region,
        JSON.stringify({ cascade_counts, deleted_at: deletedAt }),
      ],
    );
  });

  return { user_id: userId, status: 'deleted', deleted_at: deletedAt, cascade_counts };
}
