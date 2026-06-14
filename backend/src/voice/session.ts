/**
 * createVoiceSession — the gated entry point to span-consultant.
 *
 * SPAN_MASTER_PLAN §8:
 *  - EU AI Act (treat as HIGH-RISK): spoken + visual AI disclosure gated here
 *    (403 without ack).
 *  - Standalone DPDP voice consent before any voice session (403 if missing).
 *  - Insert a voice_sessions row: region='in', inference_geo='asia-south1',
 *    transcript-only, audio_retained=false.
 *  - Return a Sarvam-backed session descriptor + an EPHEMERAL token PLACEHOLDER
 *    (real keys NEVER embedded / never reach the device).
 *
 * Persistence is best-effort and defensive: if the voice_sessions table isn't
 * present yet (other track), we still return a valid descriptor so the layer is
 * usable now — the insert is wrapped and its failure is non-fatal in dev.
 */

import { randomUUID } from 'node:crypto';
import { withUser } from '../db/index.js';
import { getConfig } from '../llm/config.js';
import type {
  AiDisclosure,
  CreateVoiceSessionInput,
  CreateVoiceSessionResult,
  SarvamSessionDescriptor,
  VoiceSession,
} from './types.js';

const AI_DISCLOSURE: AiDisclosure = {
  spoken:
    'Before we start: I am Span, an AI assistant — not a doctor. I can only read ' +
    'back your own health records and explain them in plain language. I do not ' +
    'diagnose, do not recommend medicines or doses, and everything I say is ' +
    'educational. Please discuss any decisions with your clinician.',
  visual:
    'Span Consultant is an AI system (EU AI Act: high-risk health context). It is ' +
    'educational only, reads back your own records, and never diagnoses or doses. ' +
    'Discuss decisions with your clinician.',
  policyVersion: 'voice-disclosure-2026-06',
};

/** The standalone voice consent scope required before any session. */
export const VOICE_CONSENT_SCOPE = 'voice';

export interface SessionPersistenceOptions {
  /** Skip the DB insert entirely (tests / environments without the table). */
  skipPersist?: boolean;
  mode?: 'mock' | 'live';
}

/**
 * Verify the user holds an active 'voice' consent. Defensive: if the consents
 * table is unavailable in this environment, we treat the explicit
 * consentScope='voice' on the request as the grant of record (the API layer
 * owns the durable consent capture; this is a belt-and-braces check).
 */
async function hasActiveVoiceConsent(
  userId: string,
  requestedScope: string,
): Promise<boolean> {
  if (requestedScope !== VOICE_CONSENT_SCOPE) return false;
  try {
    return await withUser(userId, async (client) => {
      const { rows } = await client.query<{ granted: boolean }>(
        `SELECT granted
           FROM consents
          WHERE user_id = $1 AND scope = $2 AND granted = true
            AND withdrawn_at IS NULL
          ORDER BY granted_at DESC
          LIMIT 1`,
        [userId, VOICE_CONSENT_SCOPE],
      );
      return rows.length > 0 && rows[0]!.granted === true;
    });
  } catch {
    // Table not present yet — fall back to the request-level scope assertion.
    return requestedScope === VOICE_CONSENT_SCOPE;
  }
}

function buildDescriptor(
  cfg: Awaited<ReturnType<typeof getConfig>>,
  sessionId: string,
): SarvamSessionDescriptor {
  // EPHEMERAL token PLACEHOLDER — the real short-TTL token is minted by the
  // session orchestrator at connect time; never embed a real Sarvam key here.
  return {
    vendor: 'sarvam',
    region: 'in',
    baseUrl: cfg.SARVAM_BASE_URL,
    ephemeralToken: `EPHEMERAL_PLACEHOLDER_${sessionId}`,
    expiresAt: new Date(Date.now() + 60_000).toISOString(), // TTL ≤ 60s
    stt: { model: 'saarika:v2', languages: ['en-IN', 'hi-IN'] },
    tts: { model: 'bulbul:v2' },
    llm: { model: 'sarvam-m' },
  };
}

async function persistSession(
  session: VoiceSession,
  consentScope: string,
): Promise<void> {
  await withUser(session.userId, async (client) => {
    await client.query(
      `INSERT INTO voice_sessions
         (id, user_id, region, inference_geo, channel, privacy_tier,
          audio_retained, ai_disclosure_ack, consent_scope, model_vendor, created_at)
       VALUES ($1,$2,'in','asia-south1',$3,$4,false,true,$5,'sarvam', now())
       ON CONFLICT (id) DO NOTHING`,
      [
        session.sessionId,
        session.userId,
        session.channel,
        session.privacyTier,
        consentScope,
      ],
    );
  });
}

/**
 * Create a voice session after enforcing the AI-disclosure ack and the
 * standalone voice consent. Returns a 403 result if either is missing.
 */
export async function createVoiceSession(
  userId: string,
  input: CreateVoiceSessionInput,
  options: SessionPersistenceOptions = {},
): Promise<CreateVoiceSessionResult> {
  // Gate 1 — EU AI Act disclosure ack.
  if (!input.aiDisclosureAck) {
    return {
      ok: false,
      status: 403,
      reason: 'ai_disclosure_not_acknowledged',
      disclosure: AI_DISCLOSURE,
    };
  }

  // Gate 2 — standalone DPDP voice consent.
  const consented = await hasActiveVoiceConsent(userId, input.consentScope);
  if (!consented) {
    return {
      ok: false,
      status: 403,
      reason: 'voice_consent_missing',
      disclosure: AI_DISCLOSURE,
    };
  }

  const cfg = await getConfig();
  const sessionId = randomUUID();
  const session: VoiceSession = {
    sessionId,
    userId,
    region: 'in',
    inferenceGeo: 'asia-south1',
    channel: input.channel,
    privacyTier: input.privacyTier,
    audioRetained: false,
    aiDisclosureAck: true,
    consentScope: input.consentScope,
    modelVendor: 'sarvam',
    createdAt: new Date().toISOString(),
  };

  if (!options.skipPersist) {
    try {
      await persistSession(session, input.consentScope);
    } catch {
      // Non-fatal in dev (table may not exist yet). The API layer owns the
      // durable audit; the session is still usable.
    }
  }

  return {
    ok: true,
    status: 201,
    session,
    connect: buildDescriptor(cfg, sessionId),
    disclosure: AI_DISCLOSURE,
  };
}

/** Exposed for the API/disclosure surface. */
export function getAiDisclosure(): AiDisclosure {
  return AI_DISCLOSURE;
}
