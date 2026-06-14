---
name: Clinical Precision
source: Stitch project 14507950534942695916 (fetched 2026-06-14)
device: iPhone (MOBILE), iOS 17+ target
font: Inter (web-safe stand-in for SF Pro — use SF Pro / system font in the actual SwiftUI app)
colorMode: LIGHT
---

# Span — "Clinical Precision" design system

> Authoritative design tokens for the native SwiftUI app, exported from the Stitch
> project. Premium, restrained, medical-grade; "cite-and-defer"; never gamified.
> India-only audience. Screenshots + per-screen HTML live alongside this file.

## Core color tokens (map these to a SwiftUI `Color` asset catalog)

| Token | Hex | Use |
|---|---|---|
| `background` / surface | `#f9f9fe` | screen background (very light gray) |
| `surface-container-lowest` | `#ffffff` | cards / tiles (pure white) |
| `on-surface` (text-primary) | `#000000` / `#1a1c1f` | primary text |
| `text-secondary` | `#636366` | secondary text, disclaimers |
| `text-tertiary` | `#8E8E93` | hints |
| `outline-variant` | `#c1c6d6` | 1px hairline card borders (borders over shadows) |
| `primary` | `#005bbf` / `#1a73e8` | primary buttons, links, "Ask Span" |
| `on-primary` | `#ffffff` | text on primary |

### Status — the three-zone traffic light (organ-system health)
| Token | Hex | Meaning |
|---|---|---|
| `status-red-clinical` | `#D93025` | **Red** — outside clinical reference range (attention) |
| `status-yellow-monitor` | `#FBBC04` | **Yellow** — within clinical range but sub-optimal (monitor) |
| `status-green-optimal` | `#34A853` | **Green** — within evidence-based optimal band (on track) |
| `status-blue-low` | `#1A73E8` | **Blue** — low value flag (cool contrast to red) |
| `optimal-fill` | `#E6F4EA` | light-green chart band fill for the optimal range |
| `optimal-border` | `rgba(52,168,83,0.4)` | optimal band stroke |
| `clinical-band` | `rgba(60,60,67,0.12)` | gray chart band for the clinical reference range |

> Trend arrows are colored by **clinical impact, not direction** — a downward LDL
> arrow is Green/improving. Encode polarity per parameter (matches plan §7).

## Typography (Inter → use SF Pro / system in SwiftUI)
| Style | Size / Weight / Line | Use |
|---|---|---|
| `display-large` / `data-value-lg` | 34 / 700 / 41 | hero lab values, scores |
| `title-2` | 22 / 600 / 28 | screen headers |
| `headline` | 17 / 600 / 22 | card titles, section groups |
| `body` | 17 / 400 / 22 | body copy |
| `callout` | 16 / 400 / 21 | secondary body |
| `footnote` | 13 / 400 / 18 | the persistent "discuss with your clinician" disclaimer (secondary gray) |
| `caption-2` | 11 / 500 / 13 | citation chips, source labels |

## Spacing & shape
- Horizontal content margin **16px**; base unit **4px** (8pt rhythm); card gaps 12–16px.
- Touch targets **≥44×44pt** (HIG).
- Card / tile radius ~**0.5rem (10–12px)** continuous corners; citation chips = tighter / pill.
- **Tonal layering + 1px hairline borders, not drop shadows.** Surface = light gray, cards = white.
- Today dashboard = **2-column fluid grid** of organ-system tiles; reflow to 1 column on large Dynamic Type.

## Signature components
- **Organ-system tile:** white rounded card, SF Symbol status icon, system name, trend arrow,
  colored zone indicator (top edge or icon tint). Subtitle shows the *count* basis
  ("1 red, 2 yellow of 9 measured") — never a percentage, never a composite score.
- **Attention rail:** full-width horizontal high-priority component; red state = light-red fill +
  high-contrast border + leading alert icon.
- **Charts:** z-layered — background grid → clinical band (gray) → optimal band (light green) →
  trend line → 8pt circular data points. Flag-colored points. value==null = annotated markers.
- **Natural-frequency icons:** 10×10 grid of 100 "human" icons for "X out of 100 people" risk —
  never a bare percentage (Gigerenzer; matches plan §2.4).
- **Citation chips:** small `caption-2` chips under any claim ("Source: …"); tap → iOS `.sheet`.
- **Ask Span pill:** floating bottom-center FAB with backdrop blur (Material), on a plane above content.

## Mapping to SCREENS.md / the plan
14 designed screens, see `screens/MANIFEST.md`. They cover onboarding (Sign In with Apple,
About You, Health Context, Data & Consent), Today, Systems Overview + Metabolic/Clinical detail,
HbA1c Trend (parameter detail), Add Reports (ingestion), Doctor-Visit Prep, Biological Age, Ask Span.
This is the v1 design — the founder will iterate. Honor the resolved decisions in SPAN_MASTER_PLAN.md §11.
