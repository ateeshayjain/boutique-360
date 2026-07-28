# CLAUDE.md — Boutique 360

> Briefing packet for an AI agent. Read once, then write correct, consistent code.
> Optimised to **prevent mistakes** first. When unsure, leave `<!-- TODO: verify -->`, don't guess.
> Deep docs live in `docs/` — this file indexes them; it does not duplicate them.

---

## 1. Project Overview

- **What:** iPad-native CRM + AI design studio for a single boutique business in India (pilot stage, used daily). Designer workflow: sketch/reference → AI render → customer virtual try-on → job card for the karigar → GST invoice. Customers never touch the iPad; they receive WhatsApp messages.
- **Stack:** Swift / SwiftUI (**iOS 17+**, iPad-only) · PencilKit (sketch) · PDFKit (invoice/job-card) · **XcodeGen** (`ipad/project.yml` is the source of truth) · XCTest.
- **Backend:** Supabase Cloud (`tdnwdlrkbrtoxjzcgusg`, **ap-south-1 Mumbai**) — Postgres 17 + Auth (magic-link) + Storage + Edge Functions (`purge-expired-tryons`, `job-card-view`) + pg_cron. **28 migrations** applied. RLS on every boutique-scoped table.
- **AI:** Google Gemini (`gemini-2.5-flash-image` for render/VTO, `gemini-2.5-flash` for text). Per-boutique daily cost ceiling enforced server-side.
- **Scale:** ~85 Swift files · 18 test files · **164 tests** (pure-logic + Codable only, ~2s).
- **State:** iPad app feature-complete + stable, R1/R2/R4c/R4d shipped (slack engine, morning board, fabric-meters brief, karigar phone link). **iPad-native is the strategy** — web surfaces retired from the roadmap (July 2026; see README). Work happens on local `main`; remote push target is `origin boutique-360-ipad-app`.
- **Secrets:** `ipad/Boutique360/Configuration/Secrets.xcconfig` (GEMINI_API_KEY) is **gitignored** — never commit it. `Env.xcconfig` (Supabase URL + anon key) is tracked (anon key is RLS-protected, safe to ship).

---

## 2. Architecture & File Structure

```
boutique-360/
├── ipad/
│   ├── project.yml                 # XcodeGen spec — SOURCE OF TRUTH for the Xcode project
│   ├── Boutique360/
│   │   ├── Configuration/          # Config.swift reads Env.xcconfig + Secrets.xcconfig (gitignored)
│   │   ├── Models/                 # 12 Codable structs mirroring Postgres rows
│   │   ├── Services/               # 29 stateless `enum` namespaces (CRUD + AI + storage)
│   │   ├── Features/               # SwiftUI views, one folder per area
│   │   └── Utilities/              # Formatters, ErrorBus, Log, DesignTokens, WhatsAppShareHelper, GSTINValidator, AppEvents
│   └── Boutique360Tests/           # XCTest (pure logic + Codable round-trip)
├── supabase/migrations/            # forward-only SQL (00NN_*.sql); apply via Supabase MCP
├── docs/                           # see §6 — architecture.md, api-rpcs.md, adr/, runbooks/, etc.
└── audit-outputs/                  # whole-codebase audit reports (findings + fixes)
```

- **Data model (one struct per Postgres table; FK rules matter):**
  - `Boutique 1—* Customer 1—* Order 1—* OrderItem` · `Order 1—1 Payment(s)`
  - `Order → customer_id` is `on delete RESTRICT` (can't delete a customer with orders); most other FKs are `on delete CASCADE`.
  - `Customer 1—* {Inquiry, Design, Measurement, Appointment, ImportantDate, CustomerProfile}`
  - `Design 1—* DesignRender 1—* DesignTryOn` (tryon = customer photo, **7-day auto-purge**) · `Design/Order → JobCard`
  - `CustomerTimelineEvent` is a **derived value type** (not a table) — aggregated client-side by `CustomerTimelineService`.
- **Pattern:** MVVM-lite. Views own `@State`; `Services` are stateless `enum`s with `async throws` functions; `BoutiqueContext` is the one shared `@MainActor ObservableObject` (current boutique + staff, set at sign-in).
- **Full detail:** `docs/architecture.md` (module map, Service catalogue, 8 core design rules) and `docs/architecture-diagrams.md` (C4).

---

## 3. Coding Conventions

| Concern | Rule |
|---|---|
| **Project file** | After adding/removing a `.swift`, run `cd ipad && xcodegen generate`. Don't hand-edit `.xcodeproj`. |
| **Services** | Stateless `enum` namespaces, `static func ... async throws`. No actors, no shared state. |
| **Persistence rule** | Persist **(bucket, path)**, never signed URLs (they expire in 1 hr). Regenerate via `StorageService.signedURL(bucket:path:)` at view time. Public buckets (`vto-results`, `product-images`) are the only stable URLs. |
| **Sequences** | Order/job/inquiry numbers via `next_sequence_value` RPC (race-safe). Never `count+1` or `Int.random`. |
| **Multi-row writes** | Atomic via Postgres RPC (e.g. `create_order_with_items`). Never 3 separate client inserts. |
| **Status transitions** | Driven by enum `nextOptions` / `allowedNext` (`Order.swift`, `Inquiry.swift`). UI only offers valid transitions. |
| **Dates** | `Formatters.postgresDate` (POSIX + Asia/Kolkata) for DATE columns; `Formatters.iso8601Basic` for timestamptz; `Formatters.iso8601` (fractional) for DPDP consent. Never `DateFormatter()` ad-hoc. |
| **Money** | `Formatters.inr(_:)` for display (lakh grouping); `Money.roundedToPaise` / `equalAtPaise` for comparisons. Never `Double ==` on currency. |
| **Errors** | Load paths → `loadError` state + banner + Retry. Mutations → `do/catch` + `ErrorBus.shared.report(...)`. Never bare `try?` that swallows a meaningful failure. |
| **Logging** | `Log.<category>.<level>(...)` (`os.Logger`). Categories: auth, network, storage, ai, notifications, business, app. Use privacy specifiers (`.private` for PII). No `print()`. |
| **Design** | Tokens only: `Spacing`, `CornerRadius`, `AnimationToken` (`DesignTokens.swift`); semantic colors (`.accentColor`, `.red/.green/.orange`). No hardcoded hex, no magic padding. Respect `accessibilityReduceMotion`. |
| **Boutique scoping** | Every boutique-scoped query also passes `.eq("boutique_id", value: bid)` (RLS belt-and-braces). |
| **Tests** | XCTest, behavior-style names. Pure logic + Codable round-trip only (no network — see `docs/testing-guide.md`). |
| **Commits** | End message with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Branch off `main`; commit/push only when asked. |

---

## 4. Domain-Specific Rules (highest value — read carefully)

- **Indian number grouping:** `₹1,00,000` not `₹100,000`. `Formatters.inr` uses `Locale(en_IN)`. Never format currency by hand.
- **GST:** orders carry `subtotal`, `gst_amount`, and per-line `gst_rate`. Boutique has a `default_gst_rate` (5% typical apparel). Invoice generation reads stored `gstRate`, not a hardcoded constant. **Intra-state assumed** (CGST+SGST split); inter-state (IGST) is a known gap — the GST CSV export surfaces a spot-check warning for shipped orders.
- **GSTIN:** 15-char checksummed format; validate with `GSTINValidator` at form submit. Empty is allowed (invoices just disabled).
- **DPDP Act 2023 (legal, not optional):** customer VTO photos are sensitive data. Consent timestamp captured **at the moment of consent** (before the Gemini call), persisted to `design_tryons`. Photos auto-purge after **7 days** via the `purge-expired-tryons` Edge Function (daily pg_cron 02:30 IST) unless `saved_to_lookbook`. PII never logged. See `docs/dpdp-compliance.md`.
- **AI cost ceiling:** every Gemini call goes through `AICostMeter.checkCeiling` → `record_ai_usage` RPC (server-side, tamper-proof). Default $5/boutique/day. Image gen ≈ $0.04/call, text ≈ $0.001.
- **WhatsApp:** uses `wa.me` deep links (no Business API). Text messages only; images shared via SwiftUI `ShareLink`. Owner reviews every message before sending. India phone normalization in `WhatsAppShareHelper`. Use `customer.whatsappTarget` (NOT `customer.phone`) — falls back to phone when no separate WA # is set.
- **Email / SMS / Razorpay are credential-gated.** Pattern: `Config.<service>Enabled` boolean, button shown with discoverable hint when disabled (`"add SENDGRID_API_KEY to enable"`), never silently hidden. New external-API integrations MUST follow this pattern — see Wave 3/4 in `docs/spec-gaps-waves-1-6.md`.
- **DPDP consent is enforced in `CustomerNotifier`, not at call sites.** New send paths go through `CustomerNotifier.sendEmail/sendSMS` so the consent check is a single audit point.
- **Job card / tailor brief:** hybrid PDF — structured visual top + AI-generated **Romanized Hindi (Hinglish)** brief for the karigar. The Hinglish prompt is a deliberate UX choice (older karigars read it faster).
- **Status fields are advisory in the model** (`var status`), enforced by the UI consulting `nextOptions`. Don't leapfrog states in code.

---

## 5. Common Mistakes to Avoid (landmine map — each is a real fixed bug)

```swift
// ❌ Silent failure — "no orders" becomes indistinguishable from "network down".
//    This was THE systemic finding of the audit.
let orders = (try? await OrdersService.list()) ?? []
// ✅ Surface it
do { orders = try await OrdersService.list(); loadError = nil }
catch { loadError = error.localizedDescription }   // banner + Retry; block dependent money UI
```
```swift
// ❌ Persisting the signed URL — dead link in 1 hour (regression that shipped twice)
record.result_image_url = upload.immediateURL
// ✅ Persist the path; regenerate signed URL at view time
record.result_image_path = upload.path           // result_image_url: nil
let url = try await StorageService.signedURL(bucket: .designRenders, path: path)
```
```swift
// ❌ Swift treats "\r\n" as ONE Character — Windows/Excel CSV parses as a single line
for ch in text { if ch == "\n" { … } }
// ✅ Iterate unicodeScalars
for scalar in text.unicodeScalars { let ch = Character(scalar); … }
```

| ❌ Wrong | ✅ Right / Why |
|---|---|
| `DateFormatter()` inline for `yyyy-MM-dd` | `Formatters.postgresDate` (POSIX + IST — else DOB drifts a day at midnight) |
| `Double ==` to check "fully paid" | `Money.equalAtPaise` (sub-paise FP drift shows a phantom balance) |
| New `@Model`/table, forgot the Swift struct or RPC param | model struct ↔ migration ↔ RPC must all change together |
| Added a `.swift`, build can't find it | `cd ipad && xcodegen generate` |
| View calls `SupabaseService.client.from(...)` directly | route through a `*Service` (layer rule — grep proves Features/ has zero direct SDK calls) |
| Gemini key in URL query (`?key=`) | `x-goog-api-key` header (URLs get logged) |
| `Int.random` for human-facing numbers | `next_sequence_value` RPC (birthday-paradox collisions) |
| `customer == nil` hard-blocks VTO | route through `CustomerLinkSheet` to attach one |

---

## 6. Key Files Quick Reference (speed dial)

| Need to change… | Open |
|---|---|
| Constants / config / secrets loading | `ipad/Boutique360/Configuration/Config.swift` |
| Currency / date / money math | `Utilities/Formatters.swift` |
| Design tokens (spacing/radius/anim) | `Utilities/DesignTokens.swift` |
| Error toast pipeline | `Utilities/ErrorBus.swift` |
| Logging | `Utilities/Log.swift` |
| WhatsApp deep links | `Utilities/WhatsAppShareHelper.swift` |
| Supabase client | `Services/SupabaseService.swift` |
| Current boutique/staff session | `Services/BoutiqueContext.swift` |
| Storage upload + signed URLs + bucket enum | `Services/StorageService.swift` |
| AI render / VTO / tailor brief / style suggestions + prompts | `Services/GeminiService.swift` |
| AI cost ceiling | `Services/AICostMeter.swift` |
| Email (SendGrid) / SMS (Twilio) | `Services/SendGridClient.swift`, `Services/TwilioClient.swift` |
| Unified WA + Email + SMS dispatch (DPDP consent enforced here) | `Services/CustomerNotifier.swift` |
| Razorpay payment-link generation | `Services/RazorpayClient.swift` |
| Per-customer spend aggregator (pure, tested) | `Utilities/CustomerSpend.swift` |
| Deadline slack engine (pure, tested) + badge | `Utilities/OrderSlack.swift`, `Features/Orders/SlackBadge.swift` |
| Karigar link events + token rotation | `Services/JobCardEventsService.swift` |
| Karigar phone page (Edge Function) | `supabase/functions/job-card-view/index.ts` |
| Garment template silhouettes for sketch canvas | `Features/Designs/GarmentTemplate.swift` |
| Order create (atomic RPC) | `Services/OrdersService.swift` |
| Customer journey aggregation | `Services/CustomerTimelineService.swift` |
| GST invoice / job-card PDFs | `Services/InvoicePDFGenerator.swift`, `Services/JobCardPDFGenerator.swift` |
| Schema changes | `supabase/migrations/00NN_*.sql` (apply via Supabase MCP) |
| RPC reference | `docs/api-rpcs.md` |
| Why a foundational choice was made | `docs/adr/` (native iPad, Supabase, Gemini, magic-link, wa.me) |
| Ops playbooks | `docs/runbooks/` (bad-deploy, Gemini outage, multi-tenant onboarding) |

**Build:** `cd ipad && xcodegen generate && xcodebuild build -project Boutique360.xcodeproj -scheme Boutique360 -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)'`
**Test:** same with `test` instead of `build` (append `-only-testing:Boutique360Tests/<Suite>` to scope).
**Run:** open in Xcode, `Cmd+R`. Demo sign-in (`#if DEBUG`): "Continue as demo (dev)" button.

---

## 7. Parallelization Guide (subagent playbook)

**Independent — safe to fan out in parallel (different files, no shared edits):**
- One agent per `Services/*Service.swift` (each wraps one table/resource).
- One agent per `Features/<Area>/` view folder.
- Pure utilities (`Formatters`, `GSTINValidator`, `WhatsAppShareHelper`) + their tests.
- Each `supabase/migrations/00NN_*.sql` is append-only (pick the next free number).

**Dependent — must be sequenced (later depends on earlier):**
1. **migration** → 2. **model struct** (`Models/`) → 3. **service method** → 4. **view**. A view referencing a column the model doesn't have yet won't compile.
- `Enums`/status changes ripple into every view that switches on them — do the enum first, then dependents.
- Anything touching `project.yml` / new files must `xcodegen generate` before parallel builders run.

**Shared-edit hotspots (serialize, don't parallelize):** `ipad/project.yml`, `Models/Order.swift` (touched by orders/payments/invoice work), `Utilities/Formatters.swift`, `AanganApp`-equivalent entry (`Boutique360App.swift`).

**Recommended split for a typical feature:** 1 agent does migration+model (sequential), then fan out: 1 agent on the Service + its tests, 1 on the new View, 1 on docs/CHANGELOG. A reviewer agent merges. See the **Dynamic Workflows** guidance below.

---

## Dynamic Workflows (multi-agent orchestration)

When a task is large, parallel, adversarial, or judgment-heavy, prefer a
**dynamic workflow** — spawn separate subagents (each with its own clean
context window) and coordinate their results — instead of doing everything
in a single context window. This combats agentic laziness (quitting after
partial progress), self-preferential bias (trusting your own output), and
goal drift after compaction.

### When to reach for a workflow
Consider a workflow when ANY of these are true:
- **Scale:** many similar items (screens, endpoints, strings, files, tickets,
  test failures) that won't fit or stay accurate in one context.
- **Adversarial / verification:** output must be checked against a rubric,
  spec, or safety/correctness requirement (a second, independent opinion adds
  real value).
- **Judgment at scale:** ranking, sorting, triage, or taste-based decisions
  (naming, UX) — comparative judgment beats one-shot absolute scoring.
- **Long-running / unknown size:** loop until a stop condition (no new
  findings, no errors) rather than a fixed number of passes.

### Patterns to compose
- **Fan-out-and-synthesize:** split into many small units, run one agent each,
  then merge structured outputs (the synthesize step is a barrier).
- **Adversarial verification:** for each producer agent, run a separate
  verifier against a rubric. Add a "skeptic" agent to suppress false positives.
- **Classify-and-act:** a classifier routes each item to the right
  agent/behavior (also good for model routing: cheap model vs. capable model).
- **Generate-and-filter:** generate many candidates, then filter/dedupe/verify
  down to the best.
- **Tournament:** N agents attempt the same task differently; judge agents
  compare pairwise until a winner emerges (great for taste/design/naming).
- **Loop-until-done:** keep spawning agents until a stop condition is met.
- **Quarantine (for untrusted input):** agents that read untrusted/external
  content must NOT take privileged actions; a separate actor agent acts on
  their findings.

### Practical guidance
- Isolate risky parallel changes (e.g. large refactors/renames) by giving each
  subagent its own worktree, then have a reviewer agent merge.
- Route models deliberately: use a cheaper model for simple subtasks and a
  more capable one for hard reasoning/verification.
- Always define an explicit completion condition so agents don't stop early
  (pair with `/goal` for a hard stop).
- For recurring work (triage, verification, research), pair with `/loop`.
- Respect token budgets when one is given (e.g. "use ~10k tokens").
- Trigger words: the user saying **"ultracode"**, **"use a workflow"**, or
  **"use a quick workflow"** is an explicit request to orchestrate.

### When NOT to use a workflow
Workflows cost significantly more tokens and add coordination overhead. Default
to a normal single-agent response when ANY of these are true:
- **Routine coding:** small edits, a single bug fix, adding one screen/endpoint,
  or a focused refactor that fits comfortably in one context.
- **The task is sequential / not parallelizable:** later steps depend on earlier
  ones, so there's nothing to fan out.
- **Low stakes or easily reversible:** the cost of a small mistake is trivial and
  a second independent reviewer adds no real value.
- **Simple Q&A or explanation:** answering a question, summarizing a file, or
  explaining how something works.
- **The work fits in one context window** and won't degrade in quality — don't
  split it just to split it.
- **Tight token/time budget** where the extra subagent overhead isn't justified.
- **You're unsure it's needed:** ask "does this really need more compute or
  independent contexts?" If not, do it directly. Most everyday coding does not
  need a panel of reviewers.

When in doubt, start with a single agent; escalate to a workflow only if the
task proves too large, too error-prone, or too judgment-heavy to do well in one
context.
