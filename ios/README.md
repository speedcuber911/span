# ios — Native SwiftUI App

Native iOS client for Project Span. No Xcode project exists yet — this is the placeholder.

## Target

- **Platform:** iOS 17+
- **Language:** Swift 5.9+, SwiftUI
- **Architecture:** TBD (likely MVVM + Observation framework)

## Key frameworks

| Framework               | Use                                                        |
|-------------------------|------------------------------------------------------------|
| SwiftUI + Observation   | UI layer; `@Observable` replaces `@ObservableObject`       |
| Swift Charts            | Lab trend charts with reference + optimal bands            |
| HealthKit               | Read steps, HRV, VO2max, sleep, resting HR                 |
| VisionKit               | On-device document scan (camera → PDF artifact)            |
| Sign in with Apple      | Sole auth method; `apple_sub` is the user identifier       |
| WebRTC / AVFoundation   | Realtime voice consultant (Sarvam session)                  |
| AVSpeechSynthesizer     | On-device TTS fallback (audio stays on device)             |

## Screen spec

Full screen-by-screen specification lives in `../SCREENS.md` (root of repo).

## Design principles (from SPAN_MASTER_PLAN.md §8)

- Organ-system tiles as the top-level view — NOT a single black-box score
- Trend charts with two bands: clinical reference range + expert-opinion optimal target
- Every computed score labeled "educational — discuss with your clinician"
- Tier 3 evidence (NMN, resveratrol, etc.) shown only with explicit contested framing
- No medical logic on-device; all scoring runs server-side
- Voice audio can stay fully on-device (SpeechAnalyzer + AVSpeechSynthesizer) for privacy

## Getting started (when Xcode project exists)

1. Open `Span.xcodeproj` in Xcode 15+
2. Set your development team and bundle ID (`ai.sigiq.span`)
3. Enable HealthKit + Sign in with Apple capabilities in the target
4. Add `Config.xcconfig` with `API_BASE_URL` pointing to the EC2 instance
5. Build and run on a physical device (HealthKit requires real hardware)
