# Span — Database migrations

Plain SQL migrations for the Span PostgreSQL schema.  Run them in order with
`psql` as a superuser / migration role (which bypasses RLS).

---

## Running migrations

```bash
# Set connection vars (or put them in ~/.pgpass / .env)
export PGHOST=localhost PGPORT=5432 PGDATABASE=span

# As the migration/superuser role:
psql -U span_migration -f migrations/0001_init.sql
psql -U span_migration -f migrations/0002_rls.sql
psql -U span_migration -f migrations/0003_seed_dictionary.sql
```

All three files are idempotent in the sense that `CREATE TABLE IF NOT EXISTS`
was intentionally **not** used — re-running them on an existing DB will error
on duplicate objects, which is the correct signal.  Use a migration runner
(e.g. `node-postgres-migrate`, `flyway`, or a thin custom script reading the
`migrations/` directory in filename order) for a proper upgrade path.

The `package.json` `migrate` script is a TODO placeholder for that runner.

---

## Migration order and dependencies

| File | Contents | Depends on |
|---|---|---|
| `0001_init.sql` | All DDL: tables, indexes, FKs | pgcrypto + uuid-ossp extensions |
| `0002_rls.sql` | `ENABLE ROW LEVEL SECURITY`, `CREATE POLICY`, append-only audit grants | 0001 |
| `0003_seed_dictionary.sql` | `canonical_parameters`, `unit_rules`, `optimal_bands`, `vendor_register`, `sources` | 0001 |

---

## RLS model

**Row-Level Security** is the primary PHI isolation mechanism.  Every table
that contains user data has a policy of the form:

```sql
USING (user_id = current_setting('app.current_user_id', true)::uuid)
```

### How the API sets the variable

The TypeScript `withUser(userId, fn)` helper in `src/db/index.ts` wraps every
PHI query in a transaction and calls:

```sql
SET LOCAL app.current_user_id = '<uuid>';
```

`SET LOCAL` scopes the variable to the current transaction — it is
automatically cleared on `COMMIT` or `ROLLBACK`, so there is no risk of a
leaked session variable bleeding into a subsequent request on the same
connection pool slot.

### Two roles

| Role | Behaviour | When used |
|---|---|---|
| `span_app` | Subject to RLS on all PHI tables; `GRANT INSERT` on audit_log but `REVOKE UPDATE/DELETE` | API server + worker processes |
| `span_migration` | Superuser (bypasses RLS); not used by live application code | Migration runs only |

### Append-only audit_log

`audit_log` has RLS enabled but no `USING` filter — the app role can `INSERT`
(via an explicit `GRANT INSERT`) but `UPDATE` and `DELETE` are revoked via
`REVOKE UPDATE, DELETE ON audit_log FROM span_app`.  This means the app can
write audit events but can never scrub them.

### Non-PHI tables (no RLS)

`canonical_parameters`, `unit_rules`, `optimal_bands`, `policy_versions`,
`sources`, and `vendor_register` are shared dictionaries.  They contain no
user data and are not RLS-protected.  The app role has `SELECT`-only access.

---

## Region pin

Every PHI row has a `region text CHECK (region IN ('in', 'eu'))` column
defaulting to `'in'`.  At launch every user is India-only (`region='in'`);
the column and check constraint are kept so a future EU deployment is additive
(new EC2 + same DDL, different default/assertion).

The application layer asserts `region = 'in'` on every PHI read and write.
A row with `region = 'eu'` would only appear on the EU box.
