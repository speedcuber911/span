# Project Span

Span turns a person's scattered diagnostic history — PDFs, photos of paper records, lab
emails — into a longitudinal, organ-system view of their health, a small set of validated
defensible computed scores (PhenoAge biological age, CKD-EPI eGFR, FIB-4, TyG, and soft
ratio flags), and a clinician-grade doctor-visit prep sheet. A realtime voice consultant
("span-consultant") lets users talk through their data, grounded strictly in their own
numbers. Everything is framed as educational and cite-and-defer — never diagnostic, never
prescriptive. The app is India-only at launch, built for privacy-by-design (DPDP + GDPR
residency spine).

## Repository layout

| Path                    | What lives here                                                                 |
|-------------------------|---------------------------------------------------------------------------------|
| `backend/`              | TypeScript/Node `/v1` API + async parse/analyze worker; plain Postgres          |
| `infra/`                | CloudFormation skeleton for the single-EC2 ap-south-1 deployment                |
| `ios/`                  | Native SwiftUI iOS app (iOS 17+) — Xcode project not yet created                |
| `app/`                  | **Legacy internal PWA** (React, single-patient dev tool) — do not move or delete |
| `SPAN_MASTER_PLAN.md`   | **Source of truth** — full architecture, medical formulas, compliance spec       |
| `SCREENS.md`            | **Source of truth** — screen-by-screen iOS UI spec (referenced by `ios/`)        |
| `SCHEMA.md`             | Postgres schema reference                                                        |
| `.span-research/`       | Component design docs from the research + planning pass                          |

## Locked stack

| Concern         | Choice                                                                        |
|-----------------|-------------------------------------------------------------------------------|
| Backend         | TypeScript (Node >= 20), Fastify, ESM                                         |
| Database        | Plain PostgreSQL with Row-Level Security — **NOT Aurora**                     |
| Compute         | **One EC2** in `ap-south-1` (Mumbai) — **NOT Fargate**                        |
| Serverless glue | SQS FIFO + DLQ, S3 SSE-KMS, KMS, DynamoDB, Lambda (pay-per-use, ~$0 at rest) |
| Parse AI        | Vertex AI `asia-south1`: Google Document AI + Gemini                          |
| Voice AI        | Sarvam (all-in-India STT/LLM/TTS)                                             |
| Client          | Native SwiftUI, iOS 17+                                                       |
| Geography       | **India only** (`ap-south-1`). Region columns kept for a later EU box.        |

**HARD RULE:** India PHI may only touch `ap-south-1` / Vertex `asia-south1`. Claude /
Anthropic APIs are excluded from the India path (Bedrock-India routes cross-region).

## Getting started / Status

Infrastructure bootstrap is in progress. Current state:

- [x] Master plan + component designs complete (`SPAN_MASTER_PLAN.md`, `.span-research/`)
- [x] Repository skeleton created (`backend/`, `infra/`, `ios/`)
- [ ] `infra/span-infra.yaml` — CloudFormation template (in progress, separate agent)
- [ ] `backend/` — deps install + first migration
- [ ] `ios/` — Xcode project scaffold
- [ ] CI/CD pipeline

To contribute, read `SPAN_MASTER_PLAN.md` in full first — especially §1.2 (infrastructure
profile) and §7 (scoring engine) before touching `backend/src/analysis/`.
