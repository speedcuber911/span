# ios — Span (native SwiftUI)

Native iOS client for Project Span. Premium-but-restrained "Clinical Precision"
experience: organ-system tiles (never one composite score), three-zone traffic
light, cite-and-defer educational tone, India-only.

- **Target:** iOS 17+ · Swift 5.9+ · SwiftUI · bundle id `com.parikshit.span` · target "Span"
- **Architecture:** Observation framework (`@Observable` models, `@State` /
  `@Environment` / `@Bindable`), `NavigationStack` + type-safe `Route` enum,
  Swift Charts for trends. **Thin client — no medical logic on device:** the
  backend computes every score/band/frequency; the app renders DTOs.

## Build

There are two ways to build, and both use the same `Span/` sources.

### 1. Xcode app (runnable) — via XcodeGen
```bash
brew install xcodegen      # one time
cd ios
xcodegen generate          # produces Span.xcodeproj from project.yml
open Span.xcodeproj
```
Then set your development team, and run on a simulator or device. Capabilities
(Sign in with Apple, HealthKit, camera/mic usage strings) are declared in
`project.yml` → `Info.plist` / `Span.entitlements`.

### 2. Type-check without Xcode — via SwiftPM / swiftc
`Package.swift` compiles the same tree as a library so the code can be
type-checked headless. Because SwiftPM on a Mac defaults to the macOS sysroot,
target the iOS SDK explicitly:

```bash
cd ios
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
find Span -name '*.swift' -print0 | xargs -0 \
  xcrun swiftc -sdk "$SDK" -target arm64-apple-ios17.0-simulator -typecheck
```
This is the command used to verify the project; it currently passes with no
errors. (`swift build` alone fails to load `UIKit` because SwiftPM mixes the
macOS sysroot with the iOS target — use the `swiftc -typecheck` command above,
or just build in Xcode.)

## Networking — MockSpanAPI vs LiveSpanAPI

Every screen depends only on the `SpanAPI` protocol (`Span/Models/SpanAPI.swift`),
never a concrete client:

- **`MockSpanAPI`** — realistic sample data so the whole app RUNS and every
  `#Preview` works with no backend. This is what `SpanApp` and all previews inject.
- **`LiveSpanAPI`** — talks to the India EC2 backend at `http://3.6.234.236/v1`,
  with `URLSession` plumbing, ISO-8601 JSON decoding, and a sketched Sign-in-with-
  Apple token exchange (`exchangeApple`). Swap `MockSpanAPI()` → `LiveSpanAPI()`
  in `SpanApp.swift` to point at the real backend.

## Layout

```
Span/
  App/            SpanApp entry, Info.plist, entitlements
  DesignSystem/   Color+Span, Typography+Span, Spacing, and the reusable
                  components: OrganSystemTile, AttentionRail, CitationChip,
                  ZoneIndicator, AskSpanPill, TrafficLightDot, Sparkline, SharedViews
  Models/         DTOs (mirror /v1), SpanEnums, SpanAPI + Mock/Live, ViewModels (@Observable)
  Navigation/     Route enum, AppEnvironment (DI), RootView (TabView + floating Ask Span)
  Screens/        Today, Systems overview + detail, Parameter detail (Swift Charts),
                  Add reports, Doctor-visit prep, Biological age, Ask Span (voice),
                  Check-in, Citation sheet, and Onboarding/ (Sign in with Apple,
                  Data consent, About you, Clinical flags, Health context)
  Resources/      Assets.xcassets (AppIcon placeholder)
```

## Designs

The "Clinical Precision" design system and the 13 designed screens live in
`ios/design/`:
- `design/DESIGN_SYSTEM.md` — the tokens (implemented in `Span/DesignSystem/`).
- `design/screenshots/*.png` — the rendered comps the screens were matched to.
- `design/screens/*.html` — exact colors/text the Color tokens were taken from.

Screen specs (purpose / data / interactions / states) are in `../SCREENS.md`;
the IA + per-screen API endpoints are in `../SPAN_MASTER_PLAN.md` §6.

## Product guardrails honored in the UI

- Never a single composite score as the headline — Today is organ-system tiles.
- Tiles show a **count basis** ("1 red · 2 yellow of 8 measured"), never a percentage.
- Three-zone traffic light: Red = outside clinical range / Yellow = sub-optimal /
  Green = inside a cited optimal band (shown only where one exists).
- Biological age is **secondary / opt-in**, reached via a collapsed Today link.
- Natural frequencies ("about 23 of 100 people…") via a 10×10 icon grid — never bare %.
- Persistent footer on every content screen: *"Educational only · discuss any
  result with your clinician."*
- Citations are tiered chips → a Citation Detail sheet; Tier 3 carries contested framing.
- SF Pro / system font + Dynamic Type (Inter in the comps is the web stand-in).
