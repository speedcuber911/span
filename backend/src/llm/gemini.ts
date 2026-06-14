/**
 * Vertex Gemini client — regional, asia-south1 only.
 *
 * Takes page images/text plus the Document AI grounding and FORCES the
 * emit_lab_report function call (no free text). The system prompt is the
 * transcribe-only contract (SPAN_MASTER_PLAN §5).
 *
 * Residency: the Vertex client is built with location 'asia-south1' and the
 * regional apiEndpoint. No global/default endpoint is ever constructed. We
 * never call Anthropic / Claude here.
 *
 * The @google-cloud/vertexai SDK is imported LAZILY via an indirect specifier
 * so this module compiles and mock mode runs without the dependency installed.
 */

import {
  getConfig,
  VERTEX_LOCATION,
  VERTEX_API_ENDPOINT,
} from './config.js';
import {
  ConfigError,
  ParseError,
  EMIT_LAB_REPORT_SCHEMA,
  EMIT_LAB_REPORT_FUNCTION_NAME,
  TRANSCRIBE_ONLY_SYSTEM_PROMPT,
  type ExtractedReport,
  type GeminiFunctionDeclaration,
} from './types.js';

// ── input grounding handed to a single Gemini pass ────────────────────────────
export interface GeminiGrounding {
  /** Full OCR text from Document AI. */
  ocrText: string;
  /** A compact textual rendering of detected tables (cells joined). */
  tableText?: string;
  /** Optional page images (base64) + mime, for the multimodal path. */
  images?: Array<{ base64: string; mimeType: string }>;
  /** Optional hint context (lab guess / filename) appended to the user turn. */
  hintText?: string;
}

// ── minimal structural types for the bits of the SDK we touch ─────────────────
interface VertexPart {
  text?: string;
  inlineData?: { data: string; mimeType: string };
  functionCall?: { name: string; args: unknown };
}
interface VertexContent {
  role?: string;
  parts?: VertexPart[];
}
interface VertexCandidate {
  content?: VertexContent;
}
interface VertexGenerateResponse {
  response?: { candidates?: VertexCandidate[] };
}
interface VertexGenerativeModel {
  generateContent(req: unknown): Promise<VertexGenerateResponse>;
}
interface VertexAiInstance {
  getGenerativeModel(opts: Record<string, unknown>): VertexGenerativeModel;
}
interface VertexAiCtor {
  new (opts: {
    project: string;
    location: string;
    apiEndpoint?: string;
  }): VertexAiInstance;
}

let modelPromise: Promise<VertexGenerativeModel> | undefined;

async function getModel(): Promise<VertexGenerativeModel> {
  if (modelPromise) return modelPromise;
  modelPromise = (async () => {
    const cfg = await getConfig();
    if (!cfg.VERTEX_PROJECT) {
      throw new ConfigError('Gemini not configured: VERTEX_PROJECT is missing.');
    }
    let mod: { VertexAI: VertexAiCtor };
    try {
      const spec = '@google-cloud/vertexai';
      mod = (await import(spec)) as unknown as { VertexAI: VertexAiCtor };
    } catch (err) {
      throw new ConfigError(
        '@google-cloud/vertexai is not installed; cannot run live extraction.',
        err,
      );
    }
    // HARD residency pin: location + regional endpoint, never global.
    const vertex = new mod.VertexAI({
      project: cfg.VERTEX_PROJECT as string,
      location: VERTEX_LOCATION,
      apiEndpoint: VERTEX_API_ENDPOINT,
    });
    const declarations: GeminiFunctionDeclaration[] = [EMIT_LAB_REPORT_SCHEMA];
    return vertex.getGenerativeModel({
      model: cfg.GEMINI_MODEL,
      systemInstruction: {
        role: 'system',
        parts: [{ text: TRANSCRIBE_ONLY_SYSTEM_PROMPT }],
      },
      tools: [{ functionDeclarations: declarations }],
      // Force the model to emit the function call — no free text.
      toolConfig: {
        functionCallingConfig: {
          mode: 'ANY',
          allowedFunctionNames: [EMIT_LAB_REPORT_FUNCTION_NAME],
        },
      },
      generationConfig: { temperature: 0.0 },
    });
  })();
  return modelPromise;
}

function buildUserParts(g: GeminiGrounding): VertexPart[] {
  const parts: VertexPart[] = [];
  const lines: string[] = [
    'Transcribe this lab report into emit_lab_report. Verbatim only.',
  ];
  if (g.hintText) lines.push(`Context hint: ${g.hintText}`);
  lines.push('--- OCR TEXT ---', g.ocrText || '(none)');
  if (g.tableText) lines.push('--- DETECTED TABLES ---', g.tableText);
  parts.push({ text: lines.join('\n') });
  for (const img of g.images ?? []) {
    parts.push({ inlineData: { data: img.base64, mimeType: img.mimeType } });
  }
  return parts;
}

function extractFunctionArgs(resp: VertexGenerateResponse): unknown {
  const cands = resp.response?.candidates ?? [];
  for (const c of cands) {
    for (const p of c.content?.parts ?? []) {
      if (p.functionCall?.name === EMIT_LAB_REPORT_FUNCTION_NAME) {
        return p.functionCall.args;
      }
    }
  }
  return undefined;
}

/** Coerce raw function-call args into a well-typed ExtractedReport. */
export function coerceExtractedReport(args: unknown): ExtractedReport {
  const a = (args ?? {}) as Record<string, unknown>;
  const rawRows = Array.isArray(a.rows) ? (a.rows as unknown[]) : [];
  const rows = rawRows.map((r) => {
    const o = (r ?? {}) as Record<string, unknown>;
    const op = typeof o.value_operator === 'string' ? o.value_operator : '=';
    const operator =
      op === '<' || op === '>' || op === '<=' || op === '>=' ? op : '=';
    const flag =
      o.flag_printed === 'High' || o.flag_printed === 'Low' || o.flag_printed === 'Normal'
        ? o.flag_printed
        : null;
    return {
      parameter_raw: String(o.parameter_raw ?? ''),
      value_text: String(o.value_text ?? ''),
      value_numeric:
        typeof o.value_numeric === 'number' && Number.isFinite(o.value_numeric)
          ? o.value_numeric
          : null,
      value_operator: operator as ExtractedReport['rows'][number]['value_operator'],
      unit_raw: typeof o.unit_raw === 'string' && o.unit_raw.length ? o.unit_raw : null,
      ref_text: typeof o.ref_text === 'string' && o.ref_text.length ? o.ref_text : null,
      ref_low: typeof o.ref_low === 'number' && Number.isFinite(o.ref_low) ? o.ref_low : null,
      ref_high:
        typeof o.ref_high === 'number' && Number.isFinite(o.ref_high) ? o.ref_high : null,
      flag_printed: flag as ExtractedReport['rows'][number]['flag_printed'],
      confidence:
        typeof o.confidence === 'number' && Number.isFinite(o.confidence)
          ? Math.max(0, Math.min(1, o.confidence))
          : 0.5,
    };
  });
  return {
    lab: typeof a.lab === 'string' && a.lab.length ? a.lab : null,
    report_date:
      typeof a.report_date === 'string' && a.report_date.length ? a.report_date : null,
    rows,
  };
}

/**
 * Run ONE Gemini extraction pass. Forces emit_lab_report and returns the
 * transcribed report. Throws ParseError('extract') on failure.
 */
export async function emitLabReport(g: GeminiGrounding): Promise<ExtractedReport> {
  const model = await getModel();
  let resp: VertexGenerateResponse;
  try {
    resp = await model.generateContent({
      contents: [{ role: 'user', parts: buildUserParts(g) }],
    });
  } catch (err) {
    throw new ParseError('extract', 'Gemini generateContent failed.', err);
  }
  const args = extractFunctionArgs(resp);
  if (args === undefined) {
    throw new ParseError(
      'extract',
      'Gemini did not return the forced emit_lab_report function call.',
    );
  }
  return coerceExtractedReport(args);
}

/** Reset the lazily-built model (test seam). */
export function __resetGeminiModel(): void {
  modelPromise = undefined;
}
