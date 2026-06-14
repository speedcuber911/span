/**
 * Document AI client — regional, asia-south1 only.
 *
 * Wraps the OCR / Form-parser processor. Returns the raw OCR text plus parsed
 * tables and per-page layout so the Gemini step can ground its transcription on
 * structure (SPAN_MASTER_PLAN §5, STAGE 1).
 *
 * Residency: the processor client is constructed against the asia-south1
 * regional apiEndpoint. There is no code path that builds a global/default
 * client. If creds / processor are not configured we throw ConfigError so the
 * worker fails loudly rather than silently routing out of region.
 *
 * The @google-cloud/documentai SDK is imported LAZILY via an indirect specifier
 * so this module compiles and the rest of the pipeline (incl. mock mode) runs
 * even when the dependency is not installed.
 */

import { getConfig, DOCUMENTAI_API_ENDPOINT } from './config.js';
import { ConfigError, ParseError } from './types.js';

// ── result shape returned to the parse pipeline ───────────────────────────────
export interface OcrCell {
  text: string;
  rowSpan?: number;
  colSpan?: number;
}
export interface OcrTable {
  headerRows: OcrCell[][];
  bodyRows: OcrCell[][];
}
export interface OcrPage {
  pageNumber: number;
  width?: number;
  height?: number;
  text: string;
}
export interface OcrResult {
  text: string;
  tables: OcrTable[];
  pages: OcrPage[];
}

export interface OcrInput {
  /** Raw document bytes (PDF/PNG/JPEG). */
  bytes?: Uint8Array;
  /** Or a gs:// URI already in-region. */
  gcsUri?: string;
  /** MIME type, defaults to application/pdf. */
  mimeType?: string;
}

// ── minimal structural types for the bits of the SDK we touch ─────────────────
// (kept local so we don't statically import an uninstalled module)
interface DocAiTextAnchorSegment {
  startIndex?: string | number;
  endIndex?: string | number;
}
interface DocAiLayout {
  textAnchor?: { textSegments?: DocAiTextAnchorSegment[] };
}
interface DocAiTableCell {
  layout?: DocAiLayout;
  rowSpan?: number;
  colSpan?: number;
}
interface DocAiTableRow {
  cells?: DocAiTableCell[];
}
interface DocAiTable {
  headerRows?: DocAiTableRow[];
  bodyRows?: DocAiTableRow[];
}
interface DocAiPage {
  pageNumber?: number;
  dimension?: { width?: number; height?: number };
  layout?: DocAiLayout;
  tables?: DocAiTable[];
}
interface DocAiDocument {
  text?: string;
  pages?: DocAiPage[];
}
interface DocAiProcessResponse {
  document?: DocAiDocument;
}
interface DocAiClient {
  processDocument(req: unknown): Promise<[DocAiProcessResponse]>;
  processorPath(project: string, location: string, processor: string): string;
}
interface DocAiClientCtor {
  new (opts: { apiEndpoint: string; keyFilename?: string }): DocAiClient;
}

let clientPromise: Promise<DocAiClient> | undefined;

async function getClient(): Promise<DocAiClient> {
  if (clientPromise) return clientPromise;
  clientPromise = (async () => {
    const cfg = await getConfig();
    if (!cfg.VERTEX_PROJECT) {
      throw new ConfigError(
        'Document AI not configured: VERTEX_PROJECT is missing.',
      );
    }
    if (!cfg.DOCUMENTAI_PROCESSOR_ID) {
      throw new ConfigError(
        'Document AI not configured: DOCUMENTAI_PROCESSOR_ID is missing.',
      );
    }
    let mod: { DocumentProcessorServiceClient: DocAiClientCtor };
    try {
      const spec = '@google-cloud/documentai';
      mod = (await import(spec)) as unknown as {
        DocumentProcessorServiceClient: DocAiClientCtor;
      };
    } catch (err) {
      throw new ConfigError(
        '@google-cloud/documentai is not installed; cannot run live OCR.',
        err,
      );
    }
    // HARD residency pin: regional endpoint, never global/default.
    return new mod.DocumentProcessorServiceClient({
      apiEndpoint: DOCUMENTAI_API_ENDPOINT,
      keyFilename: cfg.GOOGLE_APPLICATION_CREDENTIALS,
    });
  })();
  return clientPromise;
}

function textFromAnchor(full: string, layout?: DocAiLayout): string {
  const segs = layout?.textAnchor?.textSegments;
  if (!segs || segs.length === 0) return '';
  let out = '';
  for (const s of segs) {
    const start = Number(s.startIndex ?? 0);
    const end = Number(s.endIndex ?? 0);
    if (end > start) out += full.slice(start, end);
  }
  return out.trim();
}

function mapTable(full: string, t: DocAiTable): OcrTable {
  const mapRow = (r: DocAiTableRow): OcrCell[] =>
    (r.cells ?? []).map((c) => ({
      text: textFromAnchor(full, c.layout),
      rowSpan: c.rowSpan,
      colSpan: c.colSpan,
    }));
  return {
    headerRows: (t.headerRows ?? []).map(mapRow),
    bodyRows: (t.bodyRows ?? []).map(mapRow),
  };
}

/**
 * Run Document AI OCR / Form parsing on a document, in-region (asia-south1).
 * Returns { text, tables, pages }.
 */
export async function ocrDocument(input: OcrInput): Promise<OcrResult> {
  if (!input.bytes && !input.gcsUri) {
    throw new ParseError('ocr', 'ocrDocument requires bytes or gcsUri.');
  }
  const cfg = await getConfig();
  const client = await getClient();
  const name = client.processorPath(
    cfg.VERTEX_PROJECT as string,
    cfg.DOCUMENTAI_PROCESSOR_LOCATION ?? 'asia-south1',
    cfg.DOCUMENTAI_PROCESSOR_ID as string,
  );
  const mimeType = input.mimeType ?? 'application/pdf';

  const request: Record<string, unknown> = { name };
  if (input.bytes) {
    request.rawDocument = {
      content: Buffer.from(input.bytes).toString('base64'),
      mimeType,
    };
  } else {
    request.gcsDocument = { gcsUri: input.gcsUri, mimeType };
  }

  let resp: DocAiProcessResponse;
  try {
    [resp] = await client.processDocument(request);
  } catch (err) {
    throw new ParseError('ocr', 'Document AI processDocument failed.', err);
  }

  const doc = resp.document ?? {};
  const full = doc.text ?? '';
  const pages: OcrPage[] = (doc.pages ?? []).map((p, i) => ({
    pageNumber: p.pageNumber ?? i + 1,
    width: p.dimension?.width,
    height: p.dimension?.height,
    text: textFromAnchor(full, p.layout),
  }));
  const tables: OcrTable[] = [];
  for (const p of doc.pages ?? []) {
    for (const t of p.tables ?? []) tables.push(mapTable(full, t));
  }

  return { text: full, tables, pages };
}

/** Reset the lazily-built client (test seam). */
export function __resetDocumentAiClient(): void {
  clientPromise = undefined;
}
