-- =============================================================================
-- Project Span — Migration 0002: Row-Level Security + append-only audit grants
-- Run as superuser / migration role (which BYPASSRLS by default as superuser).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- ROLES (conceptual — create in your provisioning runbook, not here, because
-- role passwords/grants are environment-specific.  Documented here for clarity.)
--
--   CREATE ROLE span_app      NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE LOGIN;
--   CREATE ROLE span_migration NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE LOGIN;
--   -- span_app  → subject to RLS on all PHI tables; used by the API + worker.
--   -- span_migration → runs migrations; bypasses RLS by being SUPERUSER/owner.
--
-- The app role is NEVER given BYPASSRLS.  Workers set the session variable
-- app.current_user_id from the job payload (same mechanism as the API layer).
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- STEP 1: Enable RLS on every PHI-bearing table.
--   The audit_log has no RLS filter (app_role can INSERT but never SELECT via
--   RLS — audit rows are read-only by ops, not by individual users).
-- ---------------------------------------------------------------------------

-- Identity / consent / profile
ALTER TABLE users                ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles             ENABLE ROW LEVEL SECURITY;
ALTER TABLE consents             ENABLE ROW LEVEL SECURITY;

-- Ingestion
ALTER TABLE ingestion_artifacts  ENABLE ROW LEVEL SECURITY;
ALTER TABLE ingestion_jobs       ENABLE ROW LEVEL SECURITY;
ALTER TABLE gmail_sync_state     ENABLE ROW LEVEL SECURITY;
ALTER TABLE review_tasks         ENABLE ROW LEVEL SECURITY;

-- Reports + measurements
ALTER TABLE reports              ENABLE ROW LEVEL SECURITY;
ALTER TABLE measurements         ENABLE ROW LEVEL SECURITY;
ALTER TABLE parameter_catalog    ENABLE ROW LEVEL SECURITY;

-- Analysis outputs
ALTER TABLE parameter_stats      ENABLE ROW LEVEL SECURITY;
ALTER TABLE scores               ENABLE ROW LEVEL SECURITY;
ALTER TABLE analysis_results     ENABLE ROW LEVEL SECURITY;

-- QoL
ALTER TABLE qol_entries          ENABLE ROW LEVEL SECURITY;

-- HealthKit
ALTER TABLE healthkit_samples    ENABLE ROW LEVEL SECURITY;
ALTER TABLE healthkit_anchors    ENABLE ROW LEVEL SECURITY;

-- Voice
ALTER TABLE voice_sessions       ENABLE ROW LEVEL SECURITY;
ALTER TABLE transcripts          ENABLE ROW LEVEL SECURITY;

-- Prep
ALTER TABLE prep_reports         ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- STEP 2: RLS POLICIES
--   All policies use current_setting('app.current_user_id', true)::uuid.
--   The second argument `true` makes it return NULL (not error) when the
--   variable is not set — so migrations/ops queries without the variable set
--   will see zero rows rather than a runtime error.  The migration role
--   bypasses RLS anyway.
-- ---------------------------------------------------------------------------

-- Helper macro (repeated inline to keep the file self-contained):
-- USING (user_id = current_setting('app.current_user_id', true)::uuid)

-- users -----------------------------------------------------------------------
CREATE POLICY users_isolation ON users
    USING (id = current_setting('app.current_user_id', true)::uuid);

-- profiles --------------------------------------------------------------------
CREATE POLICY profiles_isolation ON profiles
    USING (user_id = current_setting('app.current_user_id', true)::uuid);

-- consents --------------------------------------------------------------------
CREATE POLICY consents_isolation ON consents
    USING (user_id = current_setting('app.current_user_id', true)::uuid);

-- ingestion_artifacts ---------------------------------------------------------
CREATE POLICY artifacts_isolation ON ingestion_artifacts
    USING (user_id = current_setting('app.current_user_id', true)::uuid);

-- ingestion_jobs --------------------------------------------------------------
CREATE POLICY jobs_isolation ON ingestion_jobs
    USING (user_id = current_setting('app.current_user_id', true)::uuid);

-- gmail_sync_state ------------------------------------------------------------
CREATE POLICY gmail_sync_isolation ON gmail_sync_state
    USING (user_id = current_setting('app.current_user_id', true)::uuid);

-- review_tasks ----------------------------------------------------------------
CREATE POLICY review_tasks_isolation ON review_tasks
    USING (user_id = current_setting('app.current_user_id', true)::uuid);

-- reports ---------------------------------------------------------------------
CREATE POLICY reports_isolation ON reports
    USING (user_id = current_setting('app.current_user_id', true)::uuid);

-- measurements ----------------------------------------------------------------
CREATE POLICY measurements_isolation ON measurements
    USING (user_id = current_setting('app.current_user_id', true)::uuid);

-- parameter_catalog -----------------------------------------------------------
CREATE POLICY param_catalog_isolation ON parameter_catalog
    USING (user_id = current_setting('app.current_user_id', true)::uuid);

-- parameter_stats -------------------------------------------------------------
CREATE POLICY param_stats_isolation ON parameter_stats
    USING (user_id = current_setting('app.current_user_id', true)::uuid);

-- scores ----------------------------------------------------------------------
CREATE POLICY scores_isolation ON scores
    USING (user_id = current_setting('app.current_user_id', true)::uuid);

-- analysis_results ------------------------------------------------------------
CREATE POLICY analysis_results_isolation ON analysis_results
    USING (user_id = current_setting('app.current_user_id', true)::uuid);

-- qol_entries -----------------------------------------------------------------
CREATE POLICY qol_isolation ON qol_entries
    USING (user_id = current_setting('app.current_user_id', true)::uuid);

-- healthkit_samples -----------------------------------------------------------
CREATE POLICY hk_samples_isolation ON healthkit_samples
    USING (user_id = current_setting('app.current_user_id', true)::uuid);

-- healthkit_anchors -----------------------------------------------------------
CREATE POLICY hk_anchors_isolation ON healthkit_anchors
    USING (user_id = current_setting('app.current_user_id', true)::uuid);

-- voice_sessions --------------------------------------------------------------
CREATE POLICY voice_sessions_isolation ON voice_sessions
    USING (user_id = current_setting('app.current_user_id', true)::uuid);

-- transcripts -----------------------------------------------------------------
CREATE POLICY transcripts_isolation ON transcripts
    USING (user_id = current_setting('app.current_user_id', true)::uuid);

-- prep_reports ----------------------------------------------------------------
CREATE POLICY prep_reports_isolation ON prep_reports
    USING (user_id = current_setting('app.current_user_id', true)::uuid);

-- ---------------------------------------------------------------------------
-- STEP 3: audit_log — APPEND-ONLY grants
--   The app role may INSERT rows but NEVER UPDATE or DELETE them.
--   This is enforced at the DB grant level so even a compromised app process
--   cannot scrub audit entries.  Reads are ops-only (no RLS filter needed).
--
--   Run the REVOKE as superuser (the migration role is superuser or is granted
--   ownership of the table).
-- ---------------------------------------------------------------------------

-- Allow the app role to insert audit events:
GRANT INSERT ON audit_log TO span_app;

-- Explicitly revoke mutation rights from the app role:
REVOKE UPDATE, DELETE ON audit_log FROM span_app;

-- Deny mutation to PUBLIC as well (belt-and-suspenders):
REVOKE UPDATE, DELETE ON audit_log FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- STEP 4: Table-level GRANTs for span_app on PHI tables
--   Minimal privilege: SELECT + INSERT + UPDATE (no DELETE for data tables;
--   deletion is handled by the pipeline which runs as the migration/owner role).
-- ---------------------------------------------------------------------------

GRANT SELECT, INSERT, UPDATE ON
    users, profiles, consents,
    ingestion_artifacts, ingestion_jobs, outbox, gmail_sync_state, review_tasks,
    reports, measurements, parameter_catalog,
    parameter_stats, scores, analysis_results,
    qol_entries,
    healthkit_samples, healthkit_anchors,
    voice_sessions, transcripts,
    prep_reports
TO span_app;

-- Read-only tables for the app role (dictionary + citations):
GRANT SELECT ON
    canonical_parameters, unit_rules, optimal_bands,
    policy_versions, sources, vendor_register
TO span_app;

-- Sequences (for bigserial audit_log.id):
GRANT USAGE, SELECT ON SEQUENCE audit_log_id_seq TO span_app;

-- ---------------------------------------------------------------------------
-- STEP 5: FORCE RLS for the table owner (safety net — prevents the owner from
--   accidentally bypassing RLS in an app-code context if the migration role is
--   ever re-used as the connection role).
-- ---------------------------------------------------------------------------
-- Note: ALTER TABLE … FORCE ROW LEVEL SECURITY only matters when the querying
-- role is the table owner.  span_app is not the owner, so this is belt-and-
-- suspenders.  Uncomment if your setup makes span_app also the table owner:
--
-- ALTER TABLE users               FORCE ROW LEVEL SECURITY;
-- ALTER TABLE profiles            FORCE ROW LEVEL SECURITY;
-- ALTER TABLE consents            FORCE ROW LEVEL SECURITY;
-- (… repeat for all PHI tables …)
