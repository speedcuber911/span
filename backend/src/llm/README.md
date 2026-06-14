# src/llm — Vertex AI Clients (Gemini + Document AI)

Cloud AI API clients for parse/OCR. All inference stays in Vertex asia-south1 (Mumbai region)
to satisfy DPDP Indian data residency requirements.

HARD RULE from SPAN_MASTER_PLAN.md §1.1:
  India PHI may ONLY touch ap-south-1 / Vertex asia-south1.
  Claude / Anthropic APIs are EXCLUDED from the India path (Bedrock-India = global cross-region).

Responsibilities:
- Google Document AI client (asia-south1 endpoint) — structured OCR for lab PDFs
- Vertex Gemini client (asia-south1 endpoint) — multimodal extraction, normalization prompts
- Prompt templates for measurement extraction → Span standardized schema
- Confidence scoring on extracted values
- Retry + error handling for API quota / transient failures

See SPAN_MASTER_PLAN.md §5 for the full parse pipeline spec.
