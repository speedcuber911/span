# src/voice — Sarvam Voice Session

Realtime voice consultant ("span-consultant") backend.

Sarvam handles all-in-India STT / LLM / TTS — satisfies DPDP residency for voice data.
The iOS client uses WebRTC; audio never hits our EC2 (routes Sarvam ↔ device directly).

Responsibilities:
- Sarvam API session management (create, token, teardown)
- RAG context injection: fetch relevant measurements + scores from Postgres for the user,
  format as grounding context for the voice LLM
- Hard medical guardrails: never diagnose, never dose; every answer defers to a clinician
- Three-tier evidence classification enforced in prompts (Tier 1 confident / Tier 3 contested)
- Session audit logging (session_id, duration, turn count — NOT transcript content unless consented)

On-device privacy tier (iOS): Apple SpeechAnalyzer / whisper.cpp + AVSpeechSynthesizer
can handle STT/TTS locally — audio never leaves the phone in that mode.

See SPAN_MASTER_PLAN.md §6 for the full voice pipeline spec.
