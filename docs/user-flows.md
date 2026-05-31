# User Flows — Boutique 360

Diagrams for the major flows. Use Mermaid; renders on GitHub, Notion, and most Markdown viewers.

---

## Flow 1 — Authentication

```mermaid
flowchart TD
    A[App launch] --> B{Session in Keychain?}
    B -->|yes| C{Session still valid?}
    B -->|no| D[SignInView]
    C -->|yes| E[BoutiqueContext.refresh]
    C -->|no - 401| D
    D --> F{Magic link or password?}
    F -->|magic link| G[Email entered → Supabase sends link]
    G --> H[Universal link callback → handleAuthCallback]
    F -->|password DEBUG only| I[demo@boutique360.test]
    H --> E
    I --> E
    E --> J{staff_users row exists?}
    J -->|yes| K[AppShellView - Dashboard]
    J -->|no| L[Trigger creates default staff row, retry]
    L --> E
```

---

## Flow 2 — Magic moment: Sketch → AI render → VTO

```mermaid
flowchart TD
    A[Customer detail] --> B[+ New design]
    B --> C[DesignFormView: name, garment, occasion, notes]
    C --> D[DesignDetailView]
    D --> E[Sketch with Pencil]
    E --> F[SketchCanvasView - PKCanvasView]
    F --> G[Save → StorageService.upload to design-sketches bucket]
    G --> H[Design row updated with sketchImagePath]
    H --> D
    D --> I[AI render]
    I --> J[RenderView]
    J --> K[Fetch sketch via signed URL]
    K --> L[GeminiService.renderGarmentFromSketch ~30s]
    L --> M[Upload result PNG to design-renders bucket]
    M --> N[Insert design_renders row with result_image_path]
    N --> O[Display result + ShareLink]
    O --> P{Customer linked?}
    P -->|yes| Q[Virtual try-on]
    Q --> R[VTO consent capture]
    R --> S{Consent toggled + signer name?}
    S -->|no| T[Disable Generate button]
    S -->|yes| U[Capture consentAt = Date()]
    U --> V[Pick customer photo]
    V --> W[GeminiService.virtualTryOn]
    W --> X[Upload customer photo + result]
    X --> Y[Insert design_tryons row with PATHS + consent timestamp]
    Y --> Z[Display watermarked result + ShareLink]
    Z --> AA[purge_at = now + 7 days]
    AA --> BB[Daily pg_cron @ 21:00 UTC]
    BB --> CC[Edge Function purge-expired-tryons]
    CC --> DD[Delete storage objects + DB row]
```

---

## Flow 3 — Inquiry → Order → Payment → Job Card

```mermaid
flowchart LR
    subgraph Inquiry["Inquiry phase"]
        A1[New inquiry] --> A2[Consulting]
        A2 --> A3[Measurements]
        A3 --> A4[Quoted]
        A4 -->|customer confirms| A5[Confirmed]
        A4 -->|customer ghosts| AL[Lost]
    end
    subgraph Order["Order phase"]
        B1[Create order from inquiry] --> B2[Atomic RPC: order + items + inquiry link]
        B2 --> B3[Order: pending]
        B3 -->|advance taken| B4[confirmed]
        B4 --> B5[packed]
        B5 --> B6[shipped or pickup]
        B6 --> B7[delivered]
    end
    subgraph Workshop["Workshop phase"]
        C1[JobCardComposer] --> C2[Load measurements + customer]
        C2 --> C3[Add fabrics, embellishments, special notes]
        C3 --> C4[Generate Hinglish brief - Gemini]
        C4 --> C5[Edit + save]
        C5 --> C6[PDF + ShareLink → karigar]
    end
    subgraph Payment["Payments thread"]
        D1[Record payment - advance] --> D2[Record payment - balance]
        D2 --> D3[Balance ≤ 0 → reminder hidden]
    end
    Inquiry --> Order
    Order --> Workshop
    Order --> Payment
```

---

## Flow 4 — Status update + child section refresh

```mermaid
sequenceDiagram
    participant UI as OrderDetailView
    participant Svc as OrdersService
    participant DB as Supabase
    participant Bus as NotificationCenter
    participant Pay as PaymentsSectionView
    participant Alt as AlterationsSectionView
    participant Tl as OrderTimelineView

    UI->>Svc: updateStatus(orderId, .shipped)
    Svc->>DB: PATCH /orders?id=eq.X
    DB-->>Svc: updated row
    Svc-->>UI: Order
    UI->>UI: current = updated
    UI->>Bus: post(.orderDidChange, object: id)
    Bus-->>Pay: onReceive → await load()
    Bus-->>Alt: onReceive → await load()
    Bus-->>Tl: onReceive → await load()
```

---

## Flow 5 — Error surfacing pipeline (silent-failure fix)

```mermaid
flowchart TD
    A[Service call fails] --> B{Caller type?}
    B -->|UI mutation - tap| C[do/catch in Task]
    B -->|background fetch| D[loadError state in view]
    C --> E[ErrorBus.shared.report]
    D --> F[Render banner inline]
    E --> G[ErrorToastOverlay on RootView]
    G --> H[Auto-dismiss after 4s]
    F --> I[Block dependent buttons - Record payment, Create]
    I --> J[Retry button visible]
    J --> A
```

---

## Flow 6 — App foreground refresh

```mermaid
sequenceDiagram
    participant iOS
    participant Root as RootView
    participant Bus as NotificationCenter
    participant Dash as DashboardView
    participant List as Various list views

    iOS->>Root: scenePhase = .active
    Root->>Bus: post(.appDidForeground)
    Bus-->>Dash: onReceive → await load()
    Bus-->>List: onReceive → await load()
    Dash->>Dash: loadFailed = false; lastRefreshAt = now
```

---

## Flow 7 — Local notifications schedule

```mermaid
flowchart TD
    A[Dashboard .task] --> B{Auth status notDetermined?}
    B -->|yes| C[requestAuthorization prompt]
    B -->|no| D[NotificationsService.refresh]
    C --> D
    D --> E[Fetch upcoming appointments + customers]
    E --> F{fetch failed?}
    F -->|yes| G[Keep existing schedule + warn]
    F -->|no| H[Cancel all boutique360.* pending]
    H --> I[Re-arm daily 8am briefing - repeats]
    I --> J{For each scheduled appt next 7 days}
    J --> K[Schedule 1-hour-before reminder]
    K --> L{appt completed or cancelled?}
    L -->|yes| M[NotificationsService.cancelAppointmentReminder]
```

---

## Flow 8 — DPDP-Act customer-photo lifecycle

```mermaid
flowchart LR
    A[Verbal consent in store] --> B[Owner toggles consentChecked + signer name]
    B --> C[consentAt = Date - captured BEFORE network]
    C --> D[Customer photo to customer-photos bucket]
    D --> E[Gemini VTO]
    E --> F[Result to vto-results bucket]
    F --> G[Insert design_tryons row with PATHS + consentAt + purge_at = now + 7d]
    G --> H[Result shown to owner + ShareLink]
    H --> I{saved_to_lookbook?}
    I -->|no| J[Daily 02:30 IST pg_cron]
    I -->|yes| K[Indefinite retention - owner choice]
    J --> L[Edge Function: purge-expired-tryons]
    L --> M[Delete storage objects in customer-photos + vto-results]
    M --> N[Delete DB row]
    N --> O[Audit trail: deletion timestamp in Edge logs]
```

---

## Flow 9 — GST monthly export

```mermaid
flowchart TD
    A[Settings → GST report] --> B[Pick month + year]
    B --> C[Tap Export GST CSV]
    C --> D[GSTReportExporter.monthly - throws]
    D --> E{Fetch orders + customers}
    E -->|fail| F[Throw error → caller surfaces]
    E -->|ok| G[Filter orders in IST month boundary]
    G --> H[Format CSV with CGST/SGST split + RFC4180 escape]
    H --> I[Count shipped orders → interStateUnknown]
    I --> J[Write to FileManager.temporaryDirectory]
    J --> K[Return Bundle with rowCount + totals + interStateUnknown]
    K --> L[ShareLink to email CA]
    L --> M{interStateUnknown > 0?}
    M -->|yes| N[UI warning: spot-check inter-state IGST]
```

---

## Flow 10 — Customer CSV import

```mermaid
flowchart TD
    A[Settings → Import customers] --> B[fileImporter]
    B --> C[startAccessingSecurityScopedResource]
    C --> D[Read Data → UTF-8 String]
    D --> E[CustomerImportService.parse]
    E --> F[Header detection - case insensitive]
    F --> G{name column present?}
    G -->|no| H[Skip with error]
    G -->|yes| I[Parse each row with RFC4180]
    I --> J[Collect parsed + skipped]
    J --> K[importRows - per-row insert with failure isolation]
    K --> L[Report: inserted, skipped, failed]
    L --> M[UI summary inline]
```

---

## Notes

- **Why mermaid**: renders inline in GitHub PRs, Notion, VS Code preview. No image generation step. Easy to maintain.
- **Update discipline**: when you change a flow's behavior, update the diagram in the same PR. Stale flow docs are worse than missing ones.
