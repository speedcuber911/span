/**
 * Sarvam client wrapper — STT / TTS / LLM, all-in-India.
 *
 * SPAN_MASTER_PLAN §8: Sarvam is the single-vendor India voice stack (no
 * cross-border). Claude is EXCLUDED. This is a THIN wrapper: clear interfaces,
 * lazy HTTP, and a mock mode so nothing here requires a real key to compile or
 * to run tests.
 *
 * Residency: every call targets the configured Sarvam base URL (India). We
 * never call Anthropic / Claude.
 */

import { getConfig } from '../llm/config.js';

export interface SttRequest {
  audioBase64: string;
  language?: string; // e.g. 'hi-IN', 'en-IN'
}
export interface SttResponse {
  text: string;
  language: string;
}

export interface TtsRequest {
  text: string;
  language?: string;
  voice?: string;
}
export interface TtsResponse {
  audioBase64: string;
  mimeType: string;
}

export interface LlmTurn {
  role: 'system' | 'user' | 'assistant';
  content: string;
}
export interface LlmRequest {
  messages: LlmTurn[];
  temperature?: number;
}
export interface LlmResponse {
  text: string;
}

export interface SarvamClient {
  stt(req: SttRequest): Promise<SttResponse>;
  tts(req: TtsRequest): Promise<TtsResponse>;
  llm(req: LlmRequest): Promise<LlmResponse>;
}

export class SarvamConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'SarvamConfigError';
  }
}

// ── mock client ───────────────────────────────────────────────────────────────
class MockSarvamClient implements SarvamClient {
  async stt(req: SttRequest): Promise<SttResponse> {
    return { text: '[mock transcript]', language: req.language ?? 'en-IN' };
  }
  async tts(req: TtsRequest): Promise<TtsResponse> {
    return {
      audioBase64: Buffer.from(req.text).toString('base64'),
      mimeType: 'audio/wav',
    };
  }
  async llm(req: LlmRequest): Promise<LlmResponse> {
    const last = req.messages[req.messages.length - 1];
    return { text: `[mock answer to: ${last?.content ?? ''}]` };
  }
}

// ── live client (HTTP via global fetch) ───────────────────────────────────────
class HttpSarvamClient implements SarvamClient {
  constructor(
    private readonly baseUrl: string,
    private readonly apiKey: string,
  ) {}

  private async post<T>(path: string, body: unknown): Promise<T> {
    const res = await fetch(`${this.baseUrl}${path}`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'api-subscription-key': this.apiKey,
      },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      throw new Error(`Sarvam ${path} failed: ${res.status} ${res.statusText}`);
    }
    return (await res.json()) as T;
  }

  async stt(req: SttRequest): Promise<SttResponse> {
    return this.post<SttResponse>('/speech-to-text', req);
  }
  async tts(req: TtsRequest): Promise<TtsResponse> {
    return this.post<TtsResponse>('/text-to-speech', req);
  }
  async llm(req: LlmRequest): Promise<LlmResponse> {
    return this.post<LlmResponse>('/chat/completions', req);
  }
}

let cached: SarvamClient | undefined;

/**
 * Get a Sarvam client. In mock mode (or absent key) returns a mock client;
 * otherwise an HTTP client bound to the in-India base URL. Never throws on
 * construction in mock mode.
 */
export async function getSarvamClient(
  opts: { mode?: 'mock' | 'live' } = {},
): Promise<SarvamClient> {
  if (cached) return cached;
  const cfg = await getConfig();
  const mode = opts.mode ?? cfg.VOICE_MODE;
  if (mode === 'mock') {
    cached = new MockSarvamClient();
    return cached;
  }
  if (!cfg.SARVAM_API_KEY) {
    throw new SarvamConfigError(
      'SARVAM_API_KEY is not configured; cannot run live voice.',
    );
  }
  cached = new HttpSarvamClient(cfg.SARVAM_BASE_URL, cfg.SARVAM_API_KEY);
  return cached;
}

/** Reset the cached client (test seam). */
export function __resetSarvamClient(): void {
  cached = undefined;
}
