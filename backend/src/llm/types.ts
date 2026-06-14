/**
 * Project Span — LLM PARSE pipeline types.
 *
 * The CONTRACT consumed by the ingestion worker:
 *   parseReport(s3Key, hint) -> ExtractedReport
 *
 * CRITICAL (SPAN_MASTER_PLAN §5): the LLM TRANSCRIBES ONLY. It must NOT
 * convert units, canonicalize parameter names, invent reference ranges, pick
 * categories, or diagnose. All of that determinism lives downstream in the
 * worker / analysis layer. These types therefore carry only what is *printed*
 * on the page (verbatim) plus a per-field confidence.
 */

// ── value operator for censored values like "<200", "> 24" ───────────────────
export type ValueOperator = '=' | '<' | '>' | '<=' | '>=';

// ── flag exactly as PRINTED on the report (never derived here) ────────────────
export type FlagPrinted = 'High' | 'Low' | 'Normal' | null;

/**
 * One transcribed row of a lab report. Every field is "what the page says",
 * not a normalized / converted value.
 */
export interface ExtractedRow {
  /** Parameter name verbatim as printed (e.g. "HbA1c", "Vitamin B-12"). */
  parameter_raw: string;
  /** The value cell verbatim, incl. "Negative" / "<200" / "> 24" / "1.2". */
  value_text: string;
  /** Parsed numeric magnitude if the cell is numeric, else null. */
  value_numeric: number | null;
  /** Operator captured from a censored value; '=' for a plain number. */
  value_operator: ValueOperator;
  /** Unit verbatim as printed (e.g. "mg/dL", "ng/mL"), or null if none. */
  unit_raw: string | null;
  /** Reference-range cell verbatim (e.g. "3.5-5.0", "<200 IU/ml"), or null. */
  ref_text: string | null;
  /** Lower reference bound ONLY if cleanly printed as a number, else null. */
  ref_low: number | null;
  /** Upper reference bound ONLY if cleanly printed as a number, else null. */
  ref_high: number | null;
  /** Flag exactly as printed by the lab; never derived here. */
  flag_printed: FlagPrinted;
  /** Per-row transcription confidence in [0,1]. */
  confidence: number;
}

/**
 * The full transcription of one lab artifact. This is the exact shape the
 * ingestion worker expects back from parseReport().
 */
export interface ExtractedReport {
  /** Lab name as printed, or null if not confidently present. */
  lab: string | null;
  /** Report/collection date as printed (ISO-ish string), or null. */
  report_date: string | null;
  /** The transcribed rows. */
  rows: ExtractedRow[];
}

// ── hint passed in from ingestion (from ingestion.parse.requested) ────────────
export interface ParseHint {
  sender_domain?: string;
  lab_guess?: string;
  original_filename?: string;
  /** Optional MIME so the parser can pick OCR vs image handling. */
  mime_type?: string;
}

// ── typed errors so the worker can branch on failure kind ─────────────────────
export type ParseErrorCode =
  | 'config' // missing creds / processor / project
  | 'fetch' // could not get bytes from S3
  | 'ocr' // Document AI failed
  | 'extract' // Gemini extraction failed
  | 'empty' // nothing extractable
  | 'unknown';

export class ParseError extends Error {
  readonly code: ParseErrorCode;
  override readonly cause?: unknown;
  constructor(code: ParseErrorCode, message: string, cause?: unknown) {
    super(message);
    this.name = 'ParseError';
    this.code = code;
    this.cause = cause;
  }
}

/** Raised specifically when GCP/AWS configuration is absent. */
export class ConfigError extends ParseError {
  constructor(message: string, cause?: unknown) {
    super('config', message, cause);
    this.name = 'ConfigError';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EMIT_LAB_REPORT_SCHEMA
//
// The Gemini FUNCTION-CALL / responseSchema contract. We FORCE this function
// call (no free text) so the model can only emit structured transcription. The
// field set mirrors ExtractedRow exactly so the boundary stays honest.
//
// Vertex's SchemaType enum is { STRING, NUMBER, INTEGER, BOOLEAN, ARRAY,
// OBJECT } as plain string literals; we encode them as strings to avoid a
// static import of @google-cloud/vertexai (which may not be installed at
// compile time). The gemini client maps these to the SDK's FunctionDeclaration.
// ─────────────────────────────────────────────────────────────────────────────

/** Minimal structural mirror of Vertex's Schema type (avoids SDK import). */
export interface GeminiSchema {
  type: string;
  description?: string;
  nullable?: boolean;
  enum?: string[];
  format?: string;
  items?: GeminiSchema;
  properties?: Record<string, GeminiSchema>;
  required?: string[];
}

export interface GeminiFunctionDeclaration {
  name: string;
  description: string;
  parameters: GeminiSchema;
}

export const EMIT_LAB_REPORT_FUNCTION_NAME = 'emit_lab_report' as const;

const ROW_SCHEMA: GeminiSchema = {
  type: 'OBJECT',
  description: 'One transcribed lab row, verbatim from the page.',
  properties: {
    parameter_raw: {
      type: 'STRING',
      description: 'Parameter name exactly as printed. Do NOT canonicalize.',
    },
    value_text: {
      type: 'STRING',
      description:
        'The value cell verbatim, including "Negative", "<200", "> 24". Do NOT convert.',
    },
    value_numeric: {
      type: 'NUMBER',
      nullable: true,
      description: 'Numeric magnitude if the cell is a number, else null.',
    },
    value_operator: {
      type: 'STRING',
      enum: ['=', '<', '>', '<=', '>='],
      description: 'Operator captured from a censored value; "=" for a plain number.',
    },
    unit_raw: {
      type: 'STRING',
      nullable: true,
      description: 'Unit exactly as printed (e.g. "ng/mL"); null if none. Do NOT convert units.',
    },
    ref_text: {
      type: 'STRING',
      nullable: true,
      description: 'Reference-range cell verbatim, or null.',
    },
    ref_low: {
      type: 'NUMBER',
      nullable: true,
      description: 'Lower reference bound ONLY if cleanly printed; never invent it.',
    },
    ref_high: {
      type: 'NUMBER',
      nullable: true,
      description: 'Upper reference bound ONLY if cleanly printed; never invent it.',
    },
    flag_printed: {
      type: 'STRING',
      nullable: true,
      enum: ['High', 'Low', 'Normal'],
      description: 'Flag exactly as printed by the lab; null if none. Do NOT derive it.',
    },
    confidence: {
      type: 'NUMBER',
      description: 'Transcription confidence in [0,1] for this row.',
    },
  },
  required: [
    'parameter_raw',
    'value_text',
    'value_numeric',
    'value_operator',
    'unit_raw',
    'ref_text',
    'ref_low',
    'ref_high',
    'flag_printed',
    'confidence',
  ],
};

/** The forced emit_lab_report function declaration handed to Gemini. */
export const EMIT_LAB_REPORT_SCHEMA: GeminiFunctionDeclaration = {
  name: EMIT_LAB_REPORT_FUNCTION_NAME,
  description:
    'Emit the lab report transcription. Transcribe ONLY what is printed. ' +
    'Do NOT diagnose, canonicalize, convert units, or invent reference ranges.',
  parameters: {
    type: 'OBJECT',
    properties: {
      lab: {
        type: 'STRING',
        nullable: true,
        description: 'Lab name as printed, or null.',
      },
      report_date: {
        type: 'STRING',
        nullable: true,
        description: 'Report/collection date as printed, or null.',
      },
      rows: {
        type: 'ARRAY',
        description: 'All transcribed rows.',
        items: ROW_SCHEMA,
      },
    },
    required: ['lab', 'report_date', 'rows'],
  },
};

/**
 * The transcribe-only system prompt (SPAN_MASTER_PLAN §5). The single source
 * of truth for the LLM's role; imported by the gemini client.
 */
export const TRANSCRIBE_ONLY_SYSTEM_PROMPT = [
  'You are Span\'s lab-report transcriber.',
  'Transcribe ONLY what is printed on the page.',
  'Do NOT diagnose, canonicalize parameter names, convert units, or invent reference ranges.',
  'Copy parameter names, values, units, and reference ranges VERBATIM.',
  'Preserve censored values exactly: "<200" -> value_text "<200", value_operator "<".',
  'Preserve "Negative", "Trace", "Not Detected" as value_text with value_numeric null.',
  'Only set ref_low/ref_high when a numeric bound is cleanly printed; otherwise null.',
  'Only set flag_printed when the lab itself printed High/Low/Normal; otherwise null.',
  'You MUST respond by calling the emit_lab_report function. Do not produce free text.',
].join('\n');
