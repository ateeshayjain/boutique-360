# Architecture Diagrams (C4 Model)

C4 is Simon Brown's diagramming model: System Context → Container → Component → Code. We document Levels 1-3 here; Level 4 is the Swift source itself.

All diagrams use Mermaid syntax — they render in GitHub, Notion, VS Code preview, and most Markdown viewers.

---

## Level 1 — System Context

> **Who are the users? What systems does Boutique 360 talk to at the boundary?**

```mermaid
flowchart TD
    Owner["👤 Boutique owner<br/>(designer + salesperson)"]
    Customer["👤 Customer<br/>(receives WhatsApp messages)"]
    CA["👤 Chartered Accountant<br/>(receives monthly GST CSV)"]

    B360["📱 Boutique 360<br/>(iPad app + Supabase backend)"]

    Gemini["☁️ Google Gemini API<br/>(sketch→render, VTO, Hinglish brief)"]
    WhatsApp["💬 WhatsApp<br/>(via wa.me + ShareLink)"]
    Apple["☁️ Apple<br/>(TestFlight, Universal Links, Push)"]
    EmailProv["📧 Email provider<br/>(magic-link delivery)"]

    Owner -->|"uses daily<br/>iPad + Pencil"| B360
    B360 -->|"AI generation"| Gemini
    B360 -->|"deep links<br/>(text + share)"| WhatsApp
    Customer -.->|"receives via<br/>WhatsApp"| WhatsApp
    B360 -->|"magic-link signin"| EmailProv
    Owner -.->|"taps link in"| EmailProv
    B360 -->|"distributed via"| Apple
    Owner -->|"emails monthly CSV"| CA
```

**Key boundary facts:**
- Customers **never use the iPad app** — they only see WhatsApp messages the owner sends
- The CA never has app access — they only see exported CSVs
- Apple is a hard dependency (App Store / TestFlight / Universal Links)
- Magic-link email delivery is the only synchronous third-party dependency for auth

---

## Level 2 — Container

> **What are the runtime processes / data stores? Which ones depend on which?**

```mermaid
flowchart TB
    subgraph iPad["📱 iPad device"]
        App["Boutique 360 iPad app<br/>(SwiftUI + PencilKit + PDFKit)"]
        Keychain["🔐 iOS Keychain<br/>(session token)"]
        UNCenter["⏰ UNUserNotificationCenter<br/>(local reminders)"]
        App --- Keychain
        App --- UNCenter
    end

    subgraph Supabase["☁️ Supabase Cloud (ap-south-1 Mumbai)"]
        PG[("🗄️ Postgres 17<br/>32+ tables, RLS")]
        Auth["🔐 Supabase Auth<br/>(magic link)"]
        Storage["📦 Storage<br/>9 buckets"]
        EdgeFn["⚡ Edge Function<br/>purge-expired-tryons"]
        Cron["⏱️ pg_cron<br/>(daily 21:00 UTC)"]
        Auth --- PG
        Storage --- PG
        EdgeFn --- PG
        EdgeFn --- Storage
        Cron --> EdgeFn
    end

    Gemini["☁️ Gemini API<br/>generativelanguage.googleapis.com"]
    WhatsApp["💬 WhatsApp (system handler)"]

    App -->|"PostgREST<br/>(JWT-auth)"| PG
    App -->|"signed URLs<br/>upload/download"| Storage
    App -->|"magic link request<br/>+ session refresh"| Auth
    App -->|"REST + x-goog-api-key"| Gemini
    App -->|"wa.me URL<br/>ShareLink"| WhatsApp

    style App fill:#4a90e2,color:#fff
    style PG fill:#3ecf8e,color:#fff
    style Gemini fill:#fbbc04,color:#000
```

**Notes:**
- **Single iPad app process** — no companion macOS / iPhone surface yet
- **No backend service of our own** — everything we run is on Supabase
- **One Edge Function** today (`purge-expired-tryons`). More may come later (e.g., a weekly summary email to the owner).
- **pg_cron is the only scheduler** — keeps "what runs when" in one place (the migrations folder)
- **The iPad never talks to Apple in-app** — Apple is a deploy-time dependency (TestFlight) and OS-services (Keychain, Universal Links, notifications) only

---

## Level 3 — Component (iPad app internals)

> **What are the modules inside the iPad app? How do they relate?**

```mermaid
flowchart TB
    subgraph Views["📺 Features/ (SwiftUI views)"]
        AuthV["Auth"]
        DashV["Dashboard"]
        CustV["Customers"]
        OrdV["Orders"]
        DesV["Designs"]
        InqV["Inquiries"]
        JcV["JobCards"]
        DateV["Dates"]
        CalV["Calendar"]
        MeasV["Measurements"]
        SettV["Settings"]
    end

    subgraph Services["⚙️ Services/ (stateless namespaces)"]
        AuthS["AuthService<br/>(ObservableObject)"]
        Ctx["BoutiqueContext<br/>(@MainActor ObservableObject)"]
        SupaSvc["SupabaseService<br/>(client singleton)"]
        Resources["CustomersService<br/>OrdersService<br/>InquiriesService<br/>DesignsService<br/>PaymentsService<br/>JobCardsService<br/>... 22 services total"]
        Storage["StorageService<br/>(upload + signedURL)"]
        Gem["GeminiService<br/>(REST wrapper)"]
        Meter["AICostMeter<br/>(server-side cap RPC)"]
        Notif["NotificationsService<br/>(UNUserNotificationCenter)"]
        Timeline["CustomerTimelineService<br/>(aggregator)"]
        Importer["CustomerImportService"]
        Exporter["GSTReportExporter"]
    end

    subgraph Models["📐 Models/ (Codable value types)"]
        M["Boutique · Customer · Order · OrderItem ·<br/>Design · DesignRender · DesignTryOn · JobCard ·<br/>Inquiry · Alteration · Appointment · Measurement ·<br/>CustomerTimelineEvent · CustomerProfile · ImportantDate"]
    end

    subgraph Utilities["🧰 Utilities/"]
        Fmt["Formatters<br/>(INR, dates, Money)"]
        Wa["WhatsAppShareHelper"]
        Gstv["GSTINValidator"]
        Eb["ErrorBus<br/>(@MainActor toast)"]
        Ae["AppEvents<br/>(NotificationCenter)"]
        Dt["DesignTokens<br/>(Spacing/Radius/Anim)"]
    end

    subgraph Config["⚙️ Configuration/"]
        Cfg["Config.swift<br/>(reads xcconfig)"]
        Env["Env.xcconfig"]
        Sec["Secrets.xcconfig<br/>(gitignored)"]
        Cfg --- Env
        Cfg --- Sec
    end

    Views -->|"call"| Services
    Services -->|"call"| Resources
    Services -->|"return"| Models
    Views -->|"render"| Models
    Resources -->|"PostgREST/RPC"| SupaSvc
    Storage --> SupaSvc
    Notif -.->|"@MainActor"| AuthS
    Ctx -.->|"@MainActor"| AuthS
    Meter --> SupaSvc
    Gem --> Meter
    Views -->|"toast"| Eb
    Services -->|"reports errors"| Eb
    Views -->|"use"| Utilities
    Services -->|"use"| Utilities

    style Views fill:#e8f5e9
    style Services fill:#e3f2fd
    style Models fill:#fff3e0
    style Utilities fill:#fce4ec
    style Config fill:#f3e5f5
```

**Architecture rules (verified by grep, see `docs/architecture.md`):**
1. Views call Services. Services do not call Views.
2. Views never call `SupabaseService.client.from(...)` directly. Verified: `grep -rn "SupabaseService.client" Features/` returns **0 matches**.
3. Models import only Foundation (no SwiftUI). Verified after the M8 audit fix moved `Color` mappings out of `CustomerTimelineEvent`.
4. Utilities are leaf nodes — they don't depend on Services or Views.

---

## Level 3.5 — Component (Backend internals)

> **What are the runtime components inside Supabase?**

```mermaid
flowchart TB
    subgraph DB["🗄️ Postgres 17"]
        Tables[("Tables (32+):<br/>boutiques, staff_users, customers,<br/>orders, order_items, payments,<br/>inquiries, designs, design_renders,<br/>design_tryons, job_cards, alterations,<br/>important_dates, appointments,<br/>measurements, ai_usage_daily, ...")]
        RLS["RLS policies<br/>(current_boutique_id helper)"]
        RPCs["RPCs:<br/>next_sequence_value<br/>create_order_with_items<br/>next_alteration_round<br/>record_ai_usage"]
        Triggers["Triggers:<br/>staff_user_bootstrap<br/>updated_at"]
        Cron["pg_cron jobs:<br/>dpdp-purge-tryons (21:00 UTC daily)"]
        Tables --- RLS
        Tables --- RPCs
        Tables --- Triggers
    end

    subgraph Buckets["📦 Storage (9 buckets)"]
        Pub["Public:<br/>product-images<br/>vto-results (watermarked)"]
        Priv["Private:<br/>design-sketches<br/>design-renders<br/>customer-photos (7d purge)<br/>vto-uploads<br/>fabrics<br/>invoices<br/>measurements-photos"]
    end

    Auth["Supabase Auth<br/>JWT issuance + refresh"]
    PostgREST["PostgREST<br/>auto-generated REST"]

    Auth --> Tables
    PostgREST --> Tables
    PostgREST --> RPCs

    EdgeFn["Edge Function:<br/>purge-expired-tryons"]
    Cron --> EdgeFn
    EdgeFn --> Tables
    EdgeFn --> Priv

    style DB fill:#3ecf8e,color:#fff
    style Buckets fill:#ffa726,color:#fff
    style Auth fill:#42a5f5,color:#fff
    style EdgeFn fill:#ab47bc,color:#fff
```

**Hard rules:**
- **All tables use RLS** — no table is open to anon role except `loyalty_tiers` (intentionally public reference data)
- **Every boutique-scoped query goes via `current_boutique_id()`** subquery helper (migration 0020 fixed the earlier session-GUC pattern)
- **Edge Function auth bypasses JWT** (`verify_jwt = false`) because pg_cron invokes it via service role internally; the function itself re-authenticates via `SUPABASE_SERVICE_ROLE_KEY`

---

## Level 1 (alt view) — Dependency direction

A different lens on the same system: who depends on whom?

```mermaid
flowchart LR
    User["👤 Owner"]
    App["📱 iPad app"]
    SupabaseSvc["☁️ Supabase"]
    GeminiSvc["☁️ Gemini"]
    Apple["☁️ Apple platform"]
    OwnerWA["💬 Owner's WhatsApp"]

    User --> App
    App --> SupabaseSvc
    App --> GeminiSvc
    App --> Apple
    App --> OwnerWA

    SupabaseSvc -.->|"no callbacks<br/>to iPad"| App
    GeminiSvc -.->|"sync response<br/>only"| App
    Apple -.->|"system events<br/>(scenePhase, etc.)"| App

    style User fill:#fff,stroke:#000
    style App fill:#4a90e2,color:#fff
```

**The iPad app is the orchestrator.** Supabase doesn't push to it (no real-time subscriptions in use yet). Gemini is request-response only. Apple's services emit OS-level events the app responds to. The owner is the only "active" party who initiates work.

When real-time becomes a requirement (e.g., multi-device sync, customer-facing notifications from the back office), arrows would flip and the system becomes bidirectional. That's a future ADR.

---

## Diagram update discipline

Whenever you add:
- **A new external service** (a third LLM, a payments provider, a CMS) → update Level 1 + 2
- **A new internal Service** → add to Level 3 list
- **A new RPC** → update Level 3.5 + `docs/api-rpcs.md`
- **A new Edge Function** → update Level 2 + 3.5

Stale diagrams are worse than missing diagrams. If you don't have time to update, file an issue + add a `// DIAGRAM TODO` comment on the relevant code.

---

## Related

- `docs/architecture.md` — prose architecture documentation (Service catalogue, design rules)
- `docs/user-flows.md` — runtime behavior sequences (orthogonal to these structural diagrams)
- `docs/adr/` — *why* the structure is shaped this way
