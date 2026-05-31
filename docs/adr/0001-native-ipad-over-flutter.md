# ADR 0001 — Native iPad app with SwiftUI over Flutter / React Native

**Date:** 2026-05-25 (pivot decision)
**Status:** Accepted
**Deciders:** Ateeshay Jain (single-decision-maker for pilot)

---

## Context

The original spec (`docs/superpowers/specs/2026-05-25-boutique-360-design.md`) called for a web admin + web public storefront as the primary surfaces. Mid-conversation, the user revealed the actual workflow:

> "Boutique designers often use notebook + pen to sketch... [we should be] iPad-native"

The boutique owner spends most of the in-store hours **sketching designs with an Apple Pencil**. Web-on-Safari for sketching is technically possible but inferior on:
- Pressure / tilt sensitivity (only PencilKit gives full first-class Pencil data)
- Palm rejection (Safari does it partially; native does it perfectly)
- Latency (~80ms vs <30ms with PencilKit)
- Toolpicker UX (PKToolPicker is iOS-native; web equivalents are mediocre)

The owner already uses an iPad as their primary device.

Three cross-platform options were considered:
1. **Flutter** — single codebase, decent iPad story
2. **React Native** — Expo SDK, JavaScript familiarity (the original Plan 1 codebase was TypeScript)
3. **Native SwiftUI** — iOS-only, Pencil-first

---

## Decision

Build the iPad surface as a **native SwiftUI app**. Web admin and public storefront are deferred to later plans (Plan 6-8 in the roadmap) and will be Next.js — they share the Supabase backend but ship as separate codebases.

Specifically:
- SwiftUI for views (no UIKit except where wrapping PencilKit / PDFKit)
- PencilKit for sketching
- PDFKit for invoice / job-card PDFs
- iOS 17+ deployment target (the project uses `NavigationStack`, `ContentUnavailableView`, and `.searchable` in ways pre-17 doesn't support cleanly)

---

## Consequences

### What becomes easier
- **First-class Pencil experience** — pressure, tilt, palm rejection, low-latency strokes
- **HIG compliance for free** — using SwiftUI semantic styles means dark mode, Dynamic Type, VoiceOver, color contrast all inherit from system defaults
- **Native sheet / share / haptics / notifications** without bridging
- **Smaller surface area** — no JavaScript runtime, no Hermes/V8, no platform-specific build complexity
- **Apple ecosystem integration** — Keychain, universal links, ShareLink, scenePhase, future iPad multitasking all available without polyfills
- **Maintenance** — one platform, one set of bugs, one set of release notes

### What becomes harder
- **No code reuse with web** — when web admin ships, no Swift code transfers. Models will be re-declared in TypeScript (mitigated by Supabase generating types).
- **App Store gatekeeping** — submission review, possible rejections, 30% commission on in-app purchases (mitigated: payments happen out-of-band via Razorpay)
- **Hiring constraint** — needs an iOS developer for future contributions, smaller talent pool than React Native / Flutter
- **CI cost** — macOS runners are 10x the price of Linux runners for the same minutes

### What becomes impossible
- **Android version** — would require a full re-implementation. Acceptable: target market is iPad-using designers.

---

## Alternatives considered

### Flutter
- Pro: single codebase, Material + Cupertino themes, growing ecosystem
- Con: Pencil support is *adequate* but not first-class. `pen` pointer events are handled but pressure data lossy. Palm rejection requires custom gesture wiring.
- **Why rejected:** the magic-moment IS the Pencil sketch. Investing in a second-class Pencil experience to save development time on web admin is the wrong trade-off when web is already a separate app.

### React Native (Expo)
- Pro: TypeScript familiarity (Plan 1 was TypeScript), large component library
- Con: Same Pencil limitation as Flutter, plus an additional JS bridge for every interaction. Expo's PencilKit support is via a community package, not first-class.
- **Why rejected:** the original Plan 1 RN+Expo direction was abandoned the same hour the iPad-native realization landed.

### Web (PWA on Safari)
- Pro: zero install, single codebase with future web admin
- Con: Pencil API is rough. Apple's web pointer events don't expose all the data PencilKit does. Offline support requires Service Workers + careful caching.
- **Why rejected:** "the sketch IS the product" — anything that degrades the sketch experience is anti-strategy.

---

## Related

- ADR 0002 — Supabase backend (chosen partly because it serves both iPad and future web equally well)
- `docs/architecture.md` — module map showing PencilKit + PDFKit integration
- `docs/superpowers/specs/2026-05-25-boutique-360-ipad-addendum.md` — the iPad-native spec
