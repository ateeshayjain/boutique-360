# Changelog

Notable changes per release. Format roughly follows [Keep a Changelog](https://keepachangelog.com/).

---

## [Unreleased] — 2026-06-05 (Reference Photo Studio — Phase 1)

### Added
- **Reference Photo Studio** — seed a Design from a reference dress photo (Pinterest/Instagram/camera roll) instead of a hand sketch, apply fabric (photo + text description), AI-render the dress in that fabric, then flow into the existing customer virtual try-on → job card → WhatsApp pipeline.
  - `ReferenceStudioView` — reference image + fabric + generate, reachable from DesignDetailView ("Start from a photo") and the Designs list ("From inspo photo").
  - `GeminiService.renderGarmentFromReference(...)` + pure `PromptTemplates.renderGarmentFromReference(...)` (unit-tested).
  - `designs.reference_image_path` column + private `design-references` storage bucket (migration `0026`) + `DesignsService.saveReferenceImagePath`.
- **App-wide camera input fix** — new reusable `ImageInputPicker` (Camera · Library · Paste URL) replaces the library-only `PhotosPicker` in Virtual Try-On (customer photo) and Sketch Canvas (fabric). The previously-dead `NSCameraUsageDescription` permission is now actually used. URL paste fails gracefully for Instagram/Pinterest (hot-link block) with a "save to Photos" hint via pure `ImageURLValidator` (unit-tested).
- **VTO customer-link gate** — a reference-photo Design may have no customer yet; `CustomerLinkSheet` lets the owner attach one mid-flow (try-on requires a customer for consent + 7-day purge). `VirtualTryOnView.customer` is now `@State` (was `let`).

### Notes
- Recovered T2–T6 work left uncommitted during a workspace move, and implemented the missing `GeminiService` peer method (the task tracker had marked it done prematurely). Each task committed as its own logical unit.
- Phases 2 (Share Extension) and 4 (saved fabric library) remain deferred per the spec.

---

## [Unreleased] — 2026-05-28 (architecture documentation cycle)

### Architecture documentation
- **NEW: `docs/adr/`** — 5 Architecture Decision Records following Michael Nygard's format. Captures the *why* behind native iPad (vs Flutter), Supabase (vs roll-our-own), Gemini (vs OpenAI/Claude), magic-link auth (vs password), and `wa.me` deep links (vs WhatsApp Business API). Each ADR has Status / Context / Decision / Consequences / Alternatives / Risks.
- **NEW: `docs/architecture-diagrams.md`** — C4 model: System Context, Container (Supabase + iPad + Gemini), Component (iPad internals + Supabase internals), Dependency Direction. All Mermaid, all render in GitHub/Notion/VS Code.
- **NEW: `docs/observability.md`** — pillars (logs/metrics/traces), what's shipped vs deferred, alerting plan, postmortem template, performance baselines.
- **NEW: `docs/runbooks/multi-tenant-onboarding.md`** — step-by-step procedure for onboarding boutique #2+, including the **critical reminder to disable the `trg_staff_user_bootstrap` trigger** before second tenant arrives (otherwise new users land on boutique #1).

### Observability (foundation shipped, instrumentation light)
- **NEW: `Utilities/Log.swift`** — `os.Logger` namespace with 7 categories (auth, network, storage, ai, notifications, business, app). Subsystem `com.boutique360.designer.ipad`. Embeds Apple's privacy specifiers (`.public` / `.private` / `.sensitive`) so DPDP-sensitive fields can be redacted in Release.
- **Strategic log points wired** in 5 high-signal places: `AuthService.signInWithMagicLink` + `signOut`, `AICostMeter.checkCeiling` (ceiling-hit events), `OrdersService.updateStatus` (status transitions = business events), `NotificationsService.scheduleDailyBriefing`.
- The principle: **lean instrumentation**, not method-entry tracing. Add a log line when it answers a likely future question; resist the urge to log every step.

---

## [Unreleased] — 2026-05-28 (test expansion + extraction cycle)

### Tests
- **Test count: 68 → 118 cases** across 14 suites. Still pure-logic + Codable round-trip only; ~2s local, ~10 min on CI.
- **New: `DesignTokensTests`** — verifies Spacing values stay on the 8pt grid (above the micro 4pt exception) and animation durations stay in HIG ranges. Adding a 13pt padding will fail CI before merge.
- **New: `MoneyTests`** — regression coverage for the L7 audit fix. Verifies `Money.roundedToPaise` handles sub-paise drift, negative refunds, and the "fully-paid-order-shows-₹0.000001-balance" bug class.
- **New: `GSTReportExporterTests`** — 10 RFC 4180 CSV escape cases including embedded Hindi text and ₹ symbol handling.
- **New: `ModelDecodingTests`** — `Boutique.defaultGstRate` and `OrderItem.gstRate` decode with and without the new columns (forward-compat for legacy rows). Includes `Order.fulfillmentMethod` enum fallback to `.pickup` on unknown values.
- **New: `PaymentsServiceModelTests`** — Decodable shape contracts for `CapturedRow`, `PerOrderSum`, `OrderHistoryRow`, `NewPayment`. Encoding round-trip verified.
- **New: `ErrorBusTests`** — Toast Identifiable contract (new ID per report) + replace-on-new-report semantics.

### Refactors (driven by testability)
- **`Money` enum extracted** into `Utilities/Formatters.swift` with `roundedToPaise(_:)` + `equalAtPaise(_:_:)`. `PaymentsSectionView.balanceDue` now uses the shared helper instead of inline math. Reusable for future "fully paid" comparisons.
- **`GSTReportExporter.csvEscape` changed from `private` to internal** (Swift module-default) so unit tests can reach it via `@testable import`. Other escape helpers stayed private — only the testable seam was exposed.

### Documentation
- **New: `docs/testing-guide.md`** — how to run tests, what we test (and don't), how to add new tests, behavior-style naming conventions, test data hygiene rules.
- Updated `README.md` test inventory: 14 files, 118 cases, with the testing-guide link.

---

## [Unreleased] — 2026-05-28 (template-audit fix cycle)

### Architecture & Engineering
- **Architecture layering enforced**: views no longer call `SupabaseService.client.from(...)` directly. Extracted `ImportantDatesService`, `PaymentsService`, `BoutiqueService` for the 5 violations found by the template audit. Zero remaining inline SDK calls in `Features/`.
- **Gemini API key moved from URL query to `x-goog-api-key` header**. URLs get logged in proxies, error reports, and network traces — header doesn't.
- **AI cost ceiling enforced server-side**: `record_ai_usage` Postgres function + `ai_usage_daily` table track per-boutique daily Gemini cost. Default cap $5/day. Tamper-proof from the iPad — client can't reset the counter.
- **CHECK constraints added**: `order_items.qty > 0`, `order_items.unit_price >= 0`, `payments.amount > 0`. Wrong-shape data now rejected at the DB layer.

### Design / HIG
- **Design tokens introduced** (`Spacing.micro` / `.small` / `.medium` / `.large` / `.xLarge`, `CornerRadius`, `AnimationToken`). Magic numbers replaced in ErrorBus + select call sites. 8pt-grid discipline now explicit.
- **Reduced-motion respected**: ErrorBus toast and RootView auth transition wrap animation in `@Environment(\.accessibilityReduceMotion)` check. Motion-sensitive users get opacity-only fades.
- **Balance Due gets an SF symbol prefix** (`exclamationmark.circle.fill` when due, `checkmark.circle.fill` when paid). Color-blind users + grayscale viewers now get a non-color cue.
- **Accessibility labels added** to icon-only buttons (Add important date, VIP crown, ErrorBus dismiss). Audit's flagged 30-spot gap was actually ~5 real spots after correction.

### Documentation
- New `docs/runbooks/` — `bad-deploy-rollback.md` + `gemini-outage.md` + index README. Tagged for severity, with communication templates + postmortem checklists.
- New `docs/privacy-policy.md` — DPDP-compliant customer-facing policy, ready for App Store submission once boutique-specific details are filled in.
- New `.github/workflows/ipad-tests.yml` — runs `xcodebuild test` on every PR touching `ipad/**`. macOS-15 runner + iPad Pro 11" simulator.

### Tests
- All 68 unit tests still green after the layer extraction (PaymentsSectionView's typealias to `PaymentsService.OrderHistoryRow` keeps the type identity).

---

## [Unreleased] — 2026-05-26 (audit-fix cycle)

### Security & Compliance
- **DPDP Act customer-photo purge** now actually runs. Added `purge-expired-tryons` Edge Function on daily pg_cron at 02:30 IST. Previously the 7-day retention promise had no enforcement.
- VTO consent timestamp now captured at the moment the customer agrees, not after Gemini + upload finish (60-90s later). Audit-trail accuracy restored.
- `design_tryons.customer_photo_path` + `result_image_path` columns added; storage objects can now be deleted on purge (previously paths were unknown).

### Money safety
- PaymentsSectionView surfaces load errors with banner + retry, and blocks "Record payment" when load failed. Prevents owner from double-charging customer when network blinks.
- Balance rounded to paise — no sub-cent floating-point drift triggering reminder UI on fully-paid orders.
- GST CSV export now `throws` on fetch failure instead of silently producing ₹0 turnover (statutory under-filing risk).
- Inter-state shipping warning surfaced on GST export so CA can spot-check IGST vs CGST/SGST split.

### Data integrity
- Order creation is now atomic via `create_order_with_items` Postgres RPC. Previously 3 separate inserts could leave orphan order headers + unconverted inquiries.
- `RenderView` no longer persists deprecated short-lived signed URLs — only paths.
- `OrderItem.gstRate` stored explicitly; invoice generation reads it directly instead of reverse-engineering from amount + subtotal.
- Boutique `default_gst_rate` column replaces hardcoded 5%.

### UX / reliability
- Dashboard shows "Couldn't reach server — figures may be stale" banner on partial fetch failure. Previously showed ₹0 across all stats, indistinguishable from a quiet day.
- ScenePhase observer broadcasts `.appDidForeground` — dashboard + lists re-fetch when owner returns to the app after hours.
- `OrderDetailView.advance()` surfaces status-update failures via inline error and triggers `.orderDidChange` for embedded child sections to refresh.
- `ErrorBus.shared` central pipeline for non-blocking error toasts (replaces 50+ `try? await ... ?? []` silent failures across the app).
- Inquiry Kanban now offers only valid transitions per `InquiryStatus.allowedNext` — no more dragging "Delivered" back to "New".

### Performance
- Dashboard overdue-payments calculation went from N sequential queries (one per open order) to a single grouped query. Several-second freeze on dashboard load → instant.
- `DateFormatter` and `ISO8601DateFormatter` allocations inside hot loops migrated to centralized `Formatters` instances. Measurable on customer-heavy boutiques.

### Code quality
- Type design: `FulfillmentMethod` enum replaces `String?` on Order. `GarmentType.init(from:)` adds forward-compat fallback to `.other`.
- `GSTINValidator` structural regex validation at form submission.
- `CustomerTimelineEvent.ID` is now a composite struct, not string-concatenated. Model no longer imports SwiftUI (tint moved to a View extension).
- All 4 source-level compiler warnings fixed: `StorageService.upload` migrated to the new Supabase SDK signature; `PKToolPicker.shared(for:)` deprecation replaced by Coordinator-owned instance; `InvoicePDFGenerator` unused variable removed.
- `WhatsAppShareHelper` utility — universal `wa.me` deep links with India phone normalization.

### Tests added (this cycle)
- `FormattersTests` — INR lakh grouping, postgres date round-trip, ISO 8601 round-trip
- `WhatsAppShareHelperTests` — phone normalization edge cases, URL building with emoji
- `GSTINValidatorTests` — structural pattern, edge cases
- `CustomerImportServiceTests` — CSV parser RFC 4180 cases
- `InquiryStatusTests` — `allowedNext` matches the business rules
- `OrderStatusTests` — `nextOptions` correctness
- `CustomerTimelineEventTests` — ID composite hashable correctness

---

## [Pre-audit baseline] — 2026-05-25

- Job Card / Tailor Brief module shipped
- WhatsApp helper wired into 5 surfaces
- Customer Timeline (unified status feed)
- Notifications + GST CSV export + CSV customer import
- Polish: empty states, search on orders/designs, settings expansions
- 50 migrations live, RLS subquery pattern, race-safe sequences, all magic-moment flows operational

(See git log before this entry for the complete history of pre-audit work.)
