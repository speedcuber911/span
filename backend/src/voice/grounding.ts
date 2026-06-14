/**
 * VOICE grounding — the RAG spine + the two non-LLM guardrails.
 *
 * SPAN_MASTER_PLAN §8: the number a user hears is gated three times. This
 * module owns two of those gates (the third, the LLM itself, sits between):
 *
 *   1. intentRouter(text)      — emergency/symptomatic → hard-escalate BEFORE
 *                                the LLM ever runs.
 *   2. buildGroundedContext()  — RAG fetch from Postgres (via withUser, RLS) of
 *                                the user's own measurements/analysis_results;
 *                                the ONLY thing the LLM may speak from
 *                                (value+unit+ref_low+ref_high+flag+date+lab).
 *   3. groundingGuard(answer)  — refuses any numeric claim not present in the
 *                                grounded context (every spoken number must
 *                                trace to a source row).
 *
 * Educational only: never diagnose, never dose, always "discuss with your
 * clinician".
 */

import { withUser } from '../db/index.js';
import type {
  GroundedContext,
  GroundedSource,
  GuardResult,
  Intent,
  IntentResult,
} from './types.js';

// ─────────────────────────────────────────────────────────────────────────────
// 1. INTENT ROUTER
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Emergency / symptomatic phrases that MUST hard-escalate before the LLM. This
 * is intentionally conservative (high recall): a false escalate is safe, a
 * missed emergency is not.
 */
const EMERGENCY_PATTERNS: RegExp[] = [
  /\bchest pain\b/i,
  /\bcan('?| ca)?not breathe\b/i,
  /\bcan'?t breathe\b/i,
  /\b(short(ness)? of breath|struggling to breathe)\b/i,
  /\b(having|im having|i am having) a (heart attack|stroke)\b/i,
  /\b(heart attack|stroke)\b/i,
  /\bsuicid(e|al)\b/i,
  /\bkill myself\b/i,
  /\bwant to die\b/i,
  /\bend my life\b/i,
  /\boverdose\b/i,
  /\bunconscious\b/i,
  /\b(severe|heavy) bleeding\b/i,
  /\bbleeding (a lot|heavily|won'?t stop)\b/i,
  /\bseizure\b/i,
  /\banaphyla(xis|ctic)\b/i,
  /\bcall (an )?ambulance\b/i,
  /\bemergency\b/i,
  /\bnumbness on one side\b/i,
  /\bslurred speech\b/i,
];

const ONBOARDING_PATTERNS: RegExp[] = [
  /\b(my )?(height|weight|bmi)\b/i,
  /\bdo i (smoke|have diabetes)\b/i,
  /\b(i (smoke|don'?t smoke))\b/i,
  /\bblood pressure\b/i,
  /\bset up my profile\b/i,
  /\bonboard(ing)?\b/i,
];

const DATA_LOOKUP_PATTERNS: RegExp[] = [
  /\bwhat (is|was|are) my\b/i,
  /\bmy (latest|last|recent)\b/i,
  /\b(level|value|result|reading|count|trend)s?\b/i,
  /\b(hba1c|cholesterol|ldl|hdl|glucose|creatinine|vitamin|tsh|triglycerides|hemoglobin)\b/i,
  /\bhow (high|low|is) my\b/i,
];

/** The fixed safety script spoken on a hard-escalate (no LLM involvement). */
export const EMERGENCY_SCRIPT =
  'This sounds like it may be a medical emergency. I cannot help with emergencies. ' +
  'Please call your local emergency number now, or go to the nearest emergency room. ' +
  'If you are in India, dial 112.';

function anyMatch(text: string, patterns: RegExp[]): string | undefined {
  for (const p of patterns) {
    const m = p.exec(text);
    if (m) return m[0];
  }
  return undefined;
}

/**
 * Classify an utterance into data-lookup | onboarding | smalltalk | EMERGENCY.
 * Emergency wins over everything and sets hardEscalate=true.
 */
export function intentRouter(text: string): IntentResult {
  const t = (text ?? '').trim();
  const emergency = anyMatch(t, EMERGENCY_PATTERNS);
  if (emergency) {
    return { intent: 'EMERGENCY', hardEscalate: true, matched: emergency };
  }
  const onboarding = anyMatch(t, ONBOARDING_PATTERNS);
  if (onboarding) {
    return { intent: 'onboarding', hardEscalate: false, matched: onboarding };
  }
  const lookup = anyMatch(t, DATA_LOOKUP_PATTERNS);
  if (lookup) {
    return { intent: 'data-lookup', hardEscalate: false, matched: lookup };
  }
  return { intent: 'smalltalk', hardEscalate: false };
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. RAG GROUNDING
// ─────────────────────────────────────────────────────────────────────────────

interface MeasurementRow {
  parameter: string;
  value: string | number | null;
  value_text: string | null;
  unit: string | null;
  ref_low: string | number | null;
  ref_high: string | number | null;
  flag: 'High' | 'Low' | 'Normal' | null;
  date: string;
  lab: string | null;
}

function toNum(v: string | number | null): number | null {
  if (v === null || v === undefined) return null;
  const n = typeof v === 'number' ? v : Number(v);
  return Number.isFinite(n) ? n : null;
}

function rowToSource(r: MeasurementRow): GroundedSource {
  return {
    parameter: r.parameter,
    value: toNum(r.value),
    valueText: r.value_text ?? undefined,
    unit: r.unit,
    refLow: toNum(r.ref_low),
    refHigh: toNum(r.ref_high),
    flag: r.flag,
    date: typeof r.date === 'string' ? r.date : String(r.date),
    lab: r.lab,
  };
}

/**
 * Render the grounded sources as a flat context block the LLM may speak from.
 * Only value+unit+ref_low+ref_high+flag+date+lab — never derived/interpreted.
 */
export function renderContextBlock(sources: GroundedSource[]): string {
  if (sources.length === 0) {
    return 'GROUNDED_CONTEXT (empty — the user has no matching measurements):';
  }
  const lines = sources.map((s) => {
    const val = s.valueText ?? (s.value === null ? 'n/a' : String(s.value));
    const unit = s.unit ? ` ${s.unit}` : '';
    const ref =
      s.refLow !== null || s.refHigh !== null
        ? ` (ref ${s.refLow ?? '?'}–${s.refHigh ?? '?'})`
        : '';
    const flag = s.flag ? ` [${s.flag}]` : '';
    const lab = s.lab ? ` @${s.lab}` : '';
    return `- ${s.parameter}: ${val}${unit}${ref}${flag} on ${s.date}${lab}`;
  });
  return ['GROUNDED_CONTEXT (speak ONLY from these; defer to clinician):', ...lines].join(
    '\n',
  );
}

/**
 * Fetch the user's own measurements relevant to a parameter/system query and
 * build the GROUNDED_CONTEXT block. RLS-scoped via withUser. If `parameter` is
 * given, filters by an ILIKE on the raw/canonical parameter; otherwise returns
 * the most recent measurements across parameters.
 */
export async function buildGroundedContext(
  userId: string,
  query: { parameter?: string; limit?: number } = {},
): Promise<GroundedContext> {
  const limit = Math.min(Math.max(query.limit ?? 25, 1), 100);
  const sources = await withUser(userId, async (client) => {
    const params: unknown[] = [userId];
    let where = 'user_id = $1';
    if (query.parameter) {
      params.push(`%${query.parameter}%`);
      where += ` AND (parameter ILIKE $${params.length} OR parameter_raw ILIKE $${params.length})`;
    }
    params.push(limit);
    const sql = `
      SELECT parameter, value, value_text, unit, ref_low, ref_high, flag,
             date::text AS date, lab
        FROM measurements
       WHERE ${where}
       ORDER BY date DESC
       LIMIT $${params.length}`;
    const { rows } = await client.query<MeasurementRow>(sql, params);
    return rows.map(rowToSource);
  });

  return {
    userId,
    sources,
    contextBlock: renderContextBlock(sources),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. OUTPUT GROUNDING GUARD
// ─────────────────────────────────────────────────────────────────────────────

/** Pull candidate numeric tokens from text (ints, decimals, with optional %). */
function extractNumbers(text: string): string[] {
  const out: string[] = [];
  const re = /(?<![\w.])\d+(?:\.\d+)?/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text)) !== null) out.push(m[0]);
  return out;
}

/** All numeric tokens that the grounded context legitimately contains. */
function groundedNumberSet(ctx: GroundedContext): Set<string> {
  const set = new Set<string>();
  const add = (n: number | null) => {
    if (n === null) return;
    set.add(String(n));
    // normalize trailing-zero forms (5 vs 5.0)
    set.add(String(Number(n)));
  };
  for (const s of ctx.sources) {
    add(s.value);
    add(s.refLow);
    add(s.refHigh);
    if (s.valueText) for (const tok of extractNumbers(s.valueText)) set.add(tok);
    // dates carry numbers the model may legitimately echo (year/month/day)
    for (const tok of extractNumbers(s.date)) set.add(tok);
  }
  return set;
}

function numbersEqual(a: string, b: string): boolean {
  if (a === b) return true;
  const na = Number(a);
  const nb = Number(b);
  return Number.isFinite(na) && Number.isFinite(nb) && na === nb;
}

const REFUSAL_TEXT =
  "I can only share numbers that are in your records, and I don't have a source " +
  'for that. Please discuss this with your clinician.';

/**
 * Refuse any numeric claim in `answer` that does not appear in the grounded
 * context. Returns allowed=false + a safe refusal when an ungrounded number is
 * present; otherwise allowed=true and the original answer.
 *
 * Years and small list-ordinals could false-positive, so we only flag numbers
 * that look like clinical magnitudes (and are absent from the context).
 */
export function groundingGuard(answer: string, ctx: GroundedContext): GuardResult {
  const grounded = groundedNumberSet(ctx);
  const candidates = extractNumbers(answer);
  const ungrounded: string[] = [];
  for (const c of candidates) {
    let ok = false;
    for (const g of grounded) {
      if (numbersEqual(c, g)) {
        ok = true;
        break;
      }
    }
    if (!ok) ungrounded.push(c);
  }
  if (ungrounded.length > 0) {
    return {
      allowed: false,
      ungroundedNumbers: ungrounded,
      safeText: REFUSAL_TEXT,
    };
  }
  return { allowed: true, ungroundedNumbers: [], safeText: answer };
}
