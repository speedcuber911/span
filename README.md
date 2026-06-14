# Span

Most people have years of lab reports sitting in folders, email threads, and WhatsApp chats — scanned paper slips, PDFs from Tata 1mg, printouts from clinic visits. Each report is a snapshot. None of them talk to each other. You go to a doctor with a new result and neither of you knows what it looked like three years ago.

Span fixes that.

## What it does

Span ingests your entire diagnostic history — however scattered, however old — and builds a longitudinal picture of your body across organ systems. Not a number dump. A narrative: how your kidneys have tracked over a decade, whether your lipid panel has quietly drifted, what your HbA1c looked like before and after that lifestyle change.

On top of that longitudinal foundation, Span computes a small set of validated clinical scores: PhenoAge (biological age from routine bloodwork), eGFR (kidney function), FIB-4 (liver fibrosis risk), and TyG (insulin resistance proxy). Every formula is grounded in peer-reviewed sources and recomputed from your own numbers — not population averages.

When you have a doctor's appointment coming up, Span generates a prep sheet: your flagged trends, your computed scores, the questions worth asking. Not to replace the conversation — to make it better.

And when you want to explore your data in your own time, you can talk to it. Span's voice consultant lets you ask questions in plain language — "has my creatinine been stable?", "what's driving my inflammation markers?" — and get answers grounded strictly in your own history.

## What it doesn't do

Span does not diagnose. It does not prescribe. It does not tell you something is wrong. Every insight is framed as educational and explicitly deferred to a clinician. This is a deliberate product stance, not a legal disclaimer bolted on at the end.

## Who it's for

India-first. Built for the person who has been getting annual blood panels for years and has never seen them as anything other than a list of numbers in a table. Built for families managing a parent's chronic disease across multiple labs and multiple years of records. Built for anyone who wants to show up to a doctor's appointment having actually done the work.

## Privacy

Your health data stays in India. Full stop. All compute runs in `ap-south-1` (Mumbai). AI inference runs on Vertex AI `asia-south1` and Sarvam (both India-resident). No data crosses a border. The architecture is built to satisfy both DPDP and GDPR from the ground up — not retrofitted.

## Stack

| Layer | Choice |
|---|---|
| Client | Native SwiftUI, iOS 17+ |
| Backend | TypeScript (Node 20), Fastify, plain PostgreSQL |
| Compute | Single EC2 in `ap-south-1` |
| Async jobs | SQS FIFO + Lambda (pay-per-use) |
| Storage | S3 + SSE-KMS |
| Parse AI | Google Document AI + Gemini (`asia-south1`) |
| Voice AI | Sarvam (India STT/LLM/TTS) |

## Repository layout

| Path | Contents |
|---|---|
| `ios/` | Native SwiftUI app |
| `backend/` | Node API + async parse/analyze worker |
| `infra/` | CloudFormation for the ap-south-1 deployment |
| `app/` | Legacy React PWA (internal dev tool) |
| `SPAN_MASTER_PLAN.md` | Full architecture, medical formulas, compliance spec |
| `SCREENS.md` | Screen-by-screen iOS UI spec |
| `.span-research/` | Component design docs from the research pass |

Read `SPAN_MASTER_PLAN.md` before touching `backend/src/analysis/` or any scoring logic.
