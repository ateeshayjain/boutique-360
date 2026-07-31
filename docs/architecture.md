# Architecture — Boutique 360

## Stack at a glance

| Layer | Tech | Why |
|---|---|---|
| Client | SwiftUI (iOS 17+), PencilKit, PDFKit | Native iPad, Pencil-first sketching, offline-tolerant PDF generation |
| Backend | Supabase Cloud (Postgres 17 + Auth + Storage + Edge Functions) | One vendor for DB+Auth+Files+Functions; ap-south-1 Mumbai region |
| AI | Google Gemini (gemini-2.5-flash + gemini-2.5-flash-image) | Cheap, fast, accepts ref images |
| Sharing | SwiftUI ShareLink + `wa.me` deep links | No URL scheme dance, no LSApplicationQueriesSchemes |
| Build | XcodeGen + xcconfig + gitignored Secrets.xcconfig | Reproducible project file, secrets never committed |
| Migrations | SQL files in `supabase/migrations/`, applied via MCP | Schema is source-controlled; every change is a migration |

---

## Module map

```
ipad/Boutique360/
├── Boutique360App.swift            ← @main, WindowGroup, scene callbacks
├── Configuration/
│   ├── Config.swift                ← Reads Env.xcconfig + Secrets.xcconfig at launch
│   ├── Env.xcconfig                ← Supabase URL/anon key (tracked)
│   └── Secrets.xcconfig.example    ← Template for GEMINI_API_KEY (gitignored real)
├── Models/                         ← Codable structs mirroring Postgres rows
│   ├── Boutique, Customer, CustomerProfile, Measurement
│   ├── Order (+OrderItem, NewOrder, NewOrderItem, AnyCodable)
│   ├── Inquiry, Design (+Lookbook), DesignRender (+DesignTryOn)
│   ├── JobCard (+FabricLine, StageProgress)
│   ├── Alteration, Appointment
│   └── CustomerTimelineEvent       ← unified value type for journey feed
├── Services/                       ← Stateless namespaces wrapping Supabase
│   ├── SupabaseService             ← shared client
│   ├── AuthService                 ← ObservableObject, holds Session
│   ├── BoutiqueContext             ← ObservableObject, current boutique + staff role
│   ├── *Service                    ← per-resource CRUD (Customers, Orders, ...)
│   ├── StorageService              ← upload + signedURL discipline
│   ├── GeminiService               ← image + text generation
│   ├── KeychainStore               ← session persistence
│   ├── InvoicePDFGenerator         ← A4 GST invoice
│   ├── JobCardPDFGenerator         ← A4 karigar brief (structured + Hinglish)
│   ├── GSTReportExporter           ← monthly CSV for CA
│   ├── CustomerTimelineService     ← aggregates 7 sources into timeline events
│   ├── CustomerImportService       ← CSV parser + batch insert
│   └── NotificationsService        ← local 8am briefing + appt reminders
├── Features/                       ← One folder per area; SwiftUI views
│   ├── Root, Shell, Auth
│   ├── Dashboard, Customers, Inquiries, Designs, Orders
│   ├── Calendar, Dates, Measurements, JobCards, Settings
└── Utilities/
    ├── Formatters                  ← inr (en_IN lakh), postgresDate, iso8601
    ├── WhatsAppShareHelper         ← wa.me URL builder + opener
    ├── GSTINValidator              ← structural regex
    ├── ErrorBus                    ← @MainActor toast pipeline
    ├── AppEvents                   ← Notification.Name extensions
    └── DesignTokens                ← Spacing / CornerRadius / AnimationToken
```

### Service catalogue

| Service | Tables | RPCs | Used by |
|---|---|---|---|
| AuthService | n/a | n/a | RootView, BoutiqueContext |
| BoutiqueContext | staff_users, boutiques | n/a | every authenticated view |
| BoutiqueService | boutiques | n/a | SettingsView |
| CustomersService | customers | n/a | CustomersListView, OrderCreateView, JobCardComposer, … |
| CustomerProfilesService | customer_profiles | n/a | CustomerStyleProfileView |
| ImportantDatesService | important_dates | n/a | DashboardView, ImportantDatesListView, CustomerDetailView |
| MeasurementsService | customer_measurements | n/a | MeasurementFormView, JobCardComposer |
| InquiriesService | inquiries | next_sequence_value | InquiriesListView, InquiryFormView |
| OrdersService | orders, order_items | next_sequence_value, create_order_with_items | OrdersListView, OrderCreateView, OrderDetailView |
| PaymentsService | payments | n/a | PaymentsSectionView, DashboardView |
| AlterationsService | alterations | next_alteration_round | AlterationsSectionView |
| AppointmentsService | appointments | n/a | CalendarView, AppointmentFormView |
| DesignsService | designs, design_lookbooks | n/a | DesignsListView, DesignDetailView, ReferenceStudioView (`saveReferenceImagePath`) |
| DesignRendersService | design_renders | n/a | RenderView, ReferenceStudioView |
| DesignTryOnsService | design_tryons | n/a | VirtualTryOnView |
| JobCardsService | job_cards | next_sequence_value | JobCardComposer, DesignDetailView |
| StorageService | (Supabase Storage; buckets incl. `design-references`) | n/a | Render/VTO/Sketch/Reference/Invoice flows |
| GeminiService | n/a | n/a | RenderView, VirtualTryOnView, ReferenceStudioView, JobCardComposer |
| AICostMeter | ai_usage_daily | record_ai_usage | GeminiService internal |
| CustomerImportService | customers (via Service) | n/a | SettingsView import |
| GSTReportExporter | orders, customers | n/a | SettingsView export |
| CustomerTimelineService | aggregates 7 sources | n/a | CustomerDetailView Journey section |
| NotificationsService | (UNNotificationCenter) | n/a | DashboardView prime, AppointmentFormView |

**Architecture rule:** views call services; services call Supabase or third-party APIs; services do not call views. Verified by `grep -rn "SupabaseService.client" Features/` returning **zero** matches as of 2026-05-28.

---

## Core design rules

### 1. Persist `(bucket, path)`, regenerate signed URLs at view time

The signed URLs Supabase returns expire in 1 hour. Persisting them = breakage tomorrow. Rule:

```swift
let upload = try await StorageService.upload(data, to: .designRenders, path: path, …)
let record = NewDesignRender(
    result_image_url: nil,                 // never persist
    result_image_path: upload.path,        // canonical
    …
)

// At view time:
let url = try await StorageService.signedURL(bucket: .designRenders, path: render.resultImagePath!)
```

Affects: `design_renders`, `design_tryons`, `design_sketches`. Public buckets (`vto-results`, `product-images`) have stable URLs that *are* safe to persist.

### 2. Per-boutique sequences via `next_sequence_value(p_boutique_id, p_sequence_name)` RPC

Order numbers, job card numbers, inquiry numbers. Race-safe (FOR UPDATE inside) and avoids the birthday-paradox collisions of `Int.random`.

### 3. Atomic multi-row writes via Postgres RPCs

Example: `create_order_with_items(p_order, p_items, p_source_inquiry_id)` is one transaction. Three separate client calls would leave orphan order headers on partial failure.

### 4. Status state machines live in the enum, the UI consults `nextOptions`

```swift
enum OrderStatus { case pending, confirmed, packed, shipped, delivered, cancelled, returned
    var nextOptions: [OrderStatus] { /* allowed forward transitions */ }
}
```

Buttons iterate `current.status.nextOptions`. The DB itself doesn't currently enforce transitions (advisory pattern). When this becomes a real problem, add a `transition(to:)` Postgres trigger.

### 5. Date formatting is centralized in `Formatters`

`Formatters.postgresDate` is POSIX-locked + Asia/Kolkata timezone — protects against DOB drift at midnight IST. `Formatters.iso8601Basic` is the Supabase `timestamptz` format. `Formatters.iso8601` (with fractional seconds) is for DPDP consent timestamps where round-trip stability matters.

### 6. Errors surface, never swallow

The silent-failure-hunter audit identified `try? await ... ?? []` as the systemic anti-pattern. The fix:

- **Load paths**: track `loadError: String?` state, show banner, expose Retry.
- **Mutation paths**: `do/catch` with `ErrorBus.shared.report(...)` for non-blocking toast.
- **Money flows**: block dependent UI on load failure (PaymentsSectionView disables Record-payment when load failed).

### 7. RLS belt-and-braces: client also filters by `boutique_id`

Defense in depth. RLS is the authoritative boundary, but a misconfigured policy during development shouldn't leak cross-tenant data. Every query that touches a boutique-scoped table includes `.eq("boutique_id", value: bid)`.

### 8. DPDP-Act customer-photo lifecycle

1. Consent timestamp captured at the moment of consent, not after upload.
2. Storage paths persisted to `design_tryons` (not just URLs).
3. Daily pg_cron @ 03:00 IST invokes Edge Function `purge-expired-tryons` to delete expired tryons (`purge_at < now()` AND `saved_to_lookbook = false`).
4. Edge Function deletes both storage objects + DB row in one pass.

---

## Concurrency model

- SwiftUI views are `@MainActor`. Most `Task {}` blocks inherit that isolation, so calling `ErrorBus.shared.report(...)` (also `@MainActor`) doesn't require `await`.
- Services are stateless `enum` namespaces with `async throws` functions. No actors, no shared mutable state.
- `BoutiqueContext` is the one `@MainActor` `ObservableObject` with shared state — set once per session at sign-in.
- `async let` is used for fan-out parallel fetches. Local closures must return tuples (not mutate shared state) to be Swift-6 strict-concurrency compatible.

---

## Build & deploy

### Project generation
```bash
cd ipad
xcodegen generate              # writes Boutique360.xcodeproj from project.yml
open Boutique360.xcodeproj
```

### Secrets
- `ipad/Boutique360/Configuration/Env.xcconfig` (tracked): Supabase URL + anon key
- `ipad/Boutique360/Configuration/Secrets.xcconfig` (gitignored): `GEMINI_API_KEY = …`
- New devs copy `Secrets.xcconfig.example` → fill in.

### Schema changes
1. Write new `supabase/migrations/00NN_description.sql`
2. Apply via Supabase MCP `apply_migration` (or `supabase db push` once CLI is installed)
3. Update Swift model + service in same PR

### Edge Functions
- Deploy via Supabase MCP `deploy_edge_function`
- Or `supabase functions deploy <name>`
- Cron jobs registered via `pg_cron.schedule` in a migration

---

## What we deliberately don't do

- **No CocoaPods/Carthage** — only SwiftPM (via XcodeGen `packages:`)
- **No Combine** — `async/await` + SwiftUI's built-in `@State`/`@Published`
- **No third-party UI kit** — pure SwiftUI + Apple HIG
- **No analytics SDK** — for now. When we add one it'll be PostHog or Mixpanel via REST, not their iOS SDK
- **No crash reporting yet** — pilot stage. Sentry plan when public-customer-facing
- **No offline-first sync** — pilot connectivity is good enough. Will add Realm or SwiftData when a customer requires it.
