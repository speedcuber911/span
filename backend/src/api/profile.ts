/**
 * Project Span — Profile routes.
 *
 *   GET   /v1/profile          — read the caller's profile + identity facts (dob/sex).
 *   PATCH /v1/profile          — partial update of onboarding/clinical facts.
 *
 * The clinical inputs collected here UNLOCK the gated scores (SPAN_MASTER_PLAN
 * §2.2 / §7):
 *   • bmi (from height_cm + weight_kg) + diabetes_status → NAFLD-FS
 *   • smoking_status + bp_systolic + bp_treated + diabetes_status → SCORE2/ASCVD
 *   • dob/sex → PhenoAge, CKD-EPI, FIB-4 age cutoff
 *
 * dob + sex live on `users`; everything else on `profiles`.  BMI is derived
 * server-side (never trusted from the client).  All writes are audited (no PHI
 * values in audit meta).
 */

import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

import { RESIDENCY } from '../config.js';
import { ApiError, audit, authPreHandler, runAsUser, unauthorized } from './middleware.js';

// ---------------------------------------------------------------------------
// Validation.  Enum domains mirror the CHECK constraints in 0001_init.sql.
// ---------------------------------------------------------------------------
const sexEnum = z.enum(['male', 'female', 'other', 'undisclosed']);
const smokingEnum = z.enum(['never', 'former', 'current']);
const diabetesEnum = z.enum(['none', 'ifg', 'type2', 'type1', 'gestational']);

// ISO date (YYYY-MM-DD), must be a real past date.
const dobSchema = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, 'dob must be YYYY-MM-DD')
  .refine((s) => {
    const d = new Date(`${s}T00:00:00Z`);
    return !Number.isNaN(d.getTime()) && d.getTime() < Date.now();
  }, 'dob must be a valid past date');

const patchBody = z
  .object({
    // identity facts (users table)
    dob: dobSchema.optional(),
    sex: sexEnum.optional(),

    // biometrics (profiles)
    height_cm: z.number().positive().max(300).optional(),
    weight_kg: z.number().positive().max(700).optional(),

    // clinical model inputs (profiles)
    smoking_status: smokingEnum.optional(),
    bp_systolic: z.number().int().min(50).max(300).optional(),
    bp_diastolic: z.number().int().min(30).max(200).optional(),
    bp_treated: z.boolean().optional(),
    diabetes_status: diabetesEnum.optional(),
    chronic_conditions: z.array(z.string().min(1).max(120)).max(64).optional(),
    // names/classes only — NO doses (enforced by product policy, §11 decision 11).
    current_supplements: z.array(z.string().min(1).max(120)).max(64).optional(),

    // goals — free-form longevity goals; stored in field_sources jsonb bag for MVP.
    goals: z.array(z.string().min(1).max(240)).max(32).optional(),
  })
  .strict();

type PatchBody = z.infer<typeof patchBody>;

// Compute BMI = kg / m^2, rounded to 2 dp, when both inputs are known.
function computeBmi(heightCm: number | null, weightKg: number | null): number | null {
  if (heightCm == null || weightKg == null || heightCm <= 0) return null;
  const m = heightCm / 100;
  return Math.round((weightKg / (m * m)) * 100) / 100;
}

// eslint-disable-next-line @typescript-eslint/require-await
export default async function profileRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', authPreHandler);

  // GET /v1/profile -----------------------------------------------------------
  app.get('/profile', async (req) => {
    if (!req.userId) throw unauthorized();

    const data = await runAsUser(req, async (client) => {
      const uid = `current_setting('app.current_user_id', true)::uuid`;
      const userRes = await client.query<{ dob: string | null; sex: string | null }>(
        `SELECT dob, sex FROM users WHERE id = ${uid}`,
      );
      const profRes = await client.query(
        `SELECT height_cm, weight_kg, bmi, smoking_status, bp_systolic, bp_diastolic,
                bp_treated, diabetes_status, chronic_conditions, current_supplements,
                onboarding_complete, field_sources, updated_at
           FROM profiles WHERE user_id = ${uid}`,
      );
      return { identity: userRes.rows[0] ?? null, profile: profRes.rows[0] ?? null };
    });

    return data;
  });

  // PATCH /v1/profile ---------------------------------------------------------
  app.patch('/profile', async (req, reply) => {
    if (!req.userId) throw unauthorized();

    const parsed = patchBody.safeParse(req.body);
    if (!parsed.success) {
      throw new ApiError(400, 'INVALID_REQUEST', parsed.error.issues[0]?.message ?? 'Invalid profile');
    }
    const body: PatchBody = parsed.data;
    if (Object.keys(body).length === 0) {
      throw new ApiError(400, 'EMPTY_PATCH', 'No fields to update');
    }

    const changedFields = Object.keys(body);

    await runAsUser(req, async (client) => {
      const uid = `current_setting('app.current_user_id', true)::uuid`;

      // 1. Identity facts on users (dob/sex), if present.
      if (body.dob !== undefined || body.sex !== undefined) {
        await client.query(
          `UPDATE users
              SET dob = COALESCE($1, dob),
                  sex = COALESCE($2, sex),
                  updated_at = now()
            WHERE id = ${uid}`,
          [body.dob ?? null, body.sex ?? null],
        );
      }

      // 2. Read current height/weight so BMI can be recomputed from the merged set.
      const cur = await client.query<{ height_cm: number | null; weight_kg: number | null }>(
        `SELECT height_cm, weight_kg FROM profiles WHERE user_id = ${uid}`,
      );
      const curRow = cur.rows[0] ?? { height_cm: null, weight_kg: null };
      const nextHeight = body.height_cm ?? curRow.height_cm;
      const nextWeight = body.weight_kg ?? curRow.weight_kg;
      const nextBmi = computeBmi(nextHeight, nextWeight);

      // 3. Upsert profile fields.  COALESCE keeps unspecified columns untouched.
      //    `goals` is stored inside field_sources jsonb (no dedicated column).
      await client.query(
        `INSERT INTO profiles (
            user_id, region, height_cm, weight_kg, bmi,
            smoking_status, bp_systolic, bp_diastolic, bp_treated, diabetes_status,
            chronic_conditions, current_supplements, field_sources, updated_at)
         VALUES (${uid}, $1, $2, $3, $4, $5, $6, $7, $8, $9,
                 COALESCE($10, '{}'), COALESCE($11, '{}'),
                 jsonb_build_object('goals', COALESCE($12::jsonb, '[]'::jsonb)), now())
         ON CONFLICT (user_id) DO UPDATE SET
            height_cm           = COALESCE(EXCLUDED.height_cm, profiles.height_cm),
            weight_kg           = COALESCE(EXCLUDED.weight_kg, profiles.weight_kg),
            bmi                 = $4,
            smoking_status      = COALESCE(EXCLUDED.smoking_status, profiles.smoking_status),
            bp_systolic         = COALESCE(EXCLUDED.bp_systolic, profiles.bp_systolic),
            bp_diastolic        = COALESCE(EXCLUDED.bp_diastolic, profiles.bp_diastolic),
            bp_treated          = COALESCE(EXCLUDED.bp_treated, profiles.bp_treated),
            diabetes_status     = COALESCE(EXCLUDED.diabetes_status, profiles.diabetes_status),
            chronic_conditions  = COALESCE($10, profiles.chronic_conditions),
            current_supplements = COALESCE($11, profiles.current_supplements),
            field_sources       = COALESCE(profiles.field_sources, '{}'::jsonb)
                                    || jsonb_build_object('goals',
                                         COALESCE($12::jsonb, profiles.field_sources->'goals', '[]'::jsonb)),
            updated_at          = now()`,
        [
          RESIDENCY.region,
          body.height_cm ?? null,
          body.weight_kg ?? null,
          nextBmi,
          body.smoking_status ?? null,
          body.bp_systolic ?? null,
          body.bp_diastolic ?? null,
          body.bp_treated ?? null,
          body.diabetes_status ?? null,
          body.chronic_conditions ?? null,
          body.current_supplements ?? null,
          body.goals ? JSON.stringify(body.goals) : null,
        ],
      );
    });

    await audit('profile.updated', 'profiles', req.userId, {
      req,
      // field NAMES only, never their values.
      detail: { fields: changedFields },
    });

    // TODO(analysis): emit a `facts.changed` recompute trigger (bmi/diabetes/sex/dob)
    // so the analysis layer re-materializes NAFLD-FS / eGFR / PhenoAge (§7).

    return reply.code(200).send({ updated: true, fields: changedFields });
  });
}
