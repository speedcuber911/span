/**
 * Project Span — VOICE session layer types (span-consultant).
 *
 * SPAN_MASTER_PLAN §8: a modular realtime voice pipeline. Span speaks ONLY the
 * user's own retrieved values (value+unit+ref_low+ref_high+flag+date+lab); it
 * never diagnoses, never doses, always defers to a clinician. The number a user
 * hears is gated three times: intent (emergency hard-escalate), grounding (RAG
 * fetch), and output guardrail (every spoken number traces to a source row).
 *
 * EU AI Act: spoken + visual AI disclosure gated in the session API (403
 * without ack); standalone DPDP consent before any voice session. Transcript-
 * only — no audio retained.
 */

// ── session creation ──────────────────────────────────────────────────────────
export type VoiceChannel = 'webrtc' | 'text'; // text-chat fallback = same spine, no STT/TTS
export type PrivacyTier = 'cloud' | 'on_device'; // on_device = zero egress (Apple/whisper.cpp)

export interface CreateVoiceSessionInput {
  channel: VoiceChannel;
  privacyTier: PrivacyTier;
  /** EU AI Act: the spoken+visual AI disclosure must be acknowledged. */
  aiDisclosureAck: boolean;
  /** Standalone DPDP voice consent scope (e.g. 'voice'). */
  consentScope: string;
}

export type SessionRejectionReason =
  | 'ai_disclosure_not_acknowledged'
  | 'voice_consent_missing';

export interface SessionRejected {
  ok: false;
  status: 403;
  reason: SessionRejectionReason;
  /** The disclosure script to show/speak so the client can re-prompt. */
  disclosure: AiDisclosure;
}

export interface SessionCreated {
  ok: true;
  status: 201;
  session: VoiceSession;
  /** Vendor session descriptor + ephemeral token PLACEHOLDER (never a real key). */
  connect: SarvamSessionDescriptor;
  disclosure: AiDisclosure;
}

export type CreateVoiceSessionResult = SessionCreated | SessionRejected;

// ── persisted session row (subset; mirrors voice_sessions) ────────────────────
export interface VoiceSession {
  sessionId: string;
  userId: string;
  region: 'in';
  inferenceGeo: 'asia-south1';
  channel: VoiceChannel;
  privacyTier: PrivacyTier;
  /** transcript-only; audio is never retained by default. */
  audioRetained: false;
  aiDisclosureAck: true;
  consentScope: string;
  modelVendor: 'sarvam';
  createdAt: string;
}

export interface SarvamSessionDescriptor {
  vendor: 'sarvam';
  /** Region pin surfaced for auditability — all hops stay in India. */
  region: 'in';
  baseUrl: string;
  /** EPHEMERAL token PLACEHOLDER. The real short-TTL token is minted elsewhere; real keys never reach the device. */
  ephemeralToken: string;
  expiresAt: string;
  stt: { model: string; languages: string[] };
  tts: { model: string };
  llm: { model: string };
}

export interface AiDisclosure {
  /** EU AI Act high-risk treatment: spoken + visual disclosure text. */
  spoken: string;
  visual: string;
  policyVersion: string;
}

// ── realtime event contract (WebRTC data-channel) ─────────────────────────────
export type AgentState =
  | 'idle'
  | 'listening'
  | 'thinking'
  | 'speaking'
  | 'escalated';

export interface SttPartialEvent {
  type: 'stt.partial';
  text: string;
  turnId: string;
}
export interface SttFinalEvent {
  type: 'stt.final';
  text: string;
  turnId: string;
}
export interface AgentStateEvent {
  type: 'agent.state';
  state: AgentState;
}
/** A source row a spoken number traces back to (the grounding proof). */
export interface GroundedSource {
  parameter: string;
  value: number | null;
  valueText?: string;
  unit: string | null;
  refLow: number | null;
  refHigh: number | null;
  flag: 'High' | 'Low' | 'Normal' | null;
  date: string;
  lab: string | null;
}
export interface TtsCaptionEvent {
  type: 'tts.caption';
  text: string;
  turnId: string;
  /** Every spoken number must trace to one of these. */
  sources: GroundedSource[];
}
export interface EscalationEvent {
  type: 'escalation';
  /** Fixed safety script spoken before the turn ends. */
  script: string;
  reason: 'emergency';
}
export interface DisclosureEvent {
  type: 'disclosure';
  disclosure: AiDisclosure;
}

export type VoiceEvent =
  | SttPartialEvent
  | SttFinalEvent
  | AgentStateEvent
  | TtsCaptionEvent
  | EscalationEvent
  | DisclosureEvent;

// ── intent routing ────────────────────────────────────────────────────────────
export type Intent = 'data-lookup' | 'onboarding' | 'smalltalk' | 'EMERGENCY';

export interface IntentResult {
  intent: Intent;
  /** True if this must hard-escalate before the LLM ever runs. */
  hardEscalate: boolean;
  matched?: string;
}

// ── grounding ─────────────────────────────────────────────────────────────────
export interface GroundedContext {
  userId: string;
  /** The source rows the LLM may speak from. */
  sources: GroundedSource[];
  /** A flat text block injected into the LLM prompt (value+unit+ref+flag+date+lab only). */
  contextBlock: string;
}

export interface GuardResult {
  allowed: boolean;
  /** Numbers in the answer that could NOT be traced to the context. */
  ungroundedNumbers: string[];
  /** The safe text to speak (refusal if not allowed). */
  safeText: string;
}
