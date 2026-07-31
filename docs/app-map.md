# Boutique 360 — App Map

Screen-by-screen, journey-by-journey map of the app as built (June 2026).
Companion docs: `architecture.md` (module rules), `customer-journey-3-month.md`
(the Priya journey), `user-flows.md`, `spec-gaps-waves-1-6.md`.

Structure: **Shell → 10 sidebar sections → 33 views → 29 stateless services →
Supabase + Gemini + WhatsApp (+ key-gated SendGrid/Twilio/Razorpay).**
Views never touch the network directly; every read/write goes through a Service.

---

## 1. Shell & navigation

| Screen | File | Role |
|---|---|---|
| Root | `Root/RootView.swift` | Auth gate: signed-out → SignInView, signed-in → AppShellView |
| Sign in | `Auth/SignInView.swift` | Magic-link email auth (+ `#if DEBUG` demo sign-in) |
| App shell | `Shell/AppShellView.swift` | `NavigationSplitView` sidebar; 10 sections; Dashboard is default landing |

Sidebar sections: Dashboard · Calendar · Designs · Customers · Inquiries ·
Orders · Important dates · Fabrics (coming soon) · Catalog (coming soon) ·
Settings.

---

## 2. Screen inventory by section

### Dashboard (1 view)
| Screen | Purpose | Key actions |
|---|---|---|
| `DashboardView` | Exception-first morning board (R2): tiles + needs-you + pipeline strip, then revenue + appointments + stats | Tap needs-you row → order detail |

*(Shipped July 2026 — R2. Companion renderer: `MorningBoardView.swift`;
pure aggregator: `Utilities/MorningBoard.swift`.)*

### Calendar (2 views)
| Screen | Purpose | Key actions |
|---|---|---|
| `CalendarView` | Appointments month/list | Add/edit appointment |
| `AppointmentFormView` | Create/edit appointment | Link to customer |

### Designs — the studio (10 views)
| Screen | Purpose | Key actions |
|---|---|---|
| `DesignsListView` | Grid board of all designs | "New" / "From inspo photo" |
| `DesignFormView` | Name, garment type, occasion, notes | Create/edit design |
| `DesignDetailView` | Hub for one design | Sketch · Start-from-photo · AI render · Try-on · Job card |
| `SketchCanvasView` | PencilKit canvas + fabric photo overlays + garment templates | Draw, add fabric (camera/library), pick template, save raster |
| `GarmentTemplate` | Kurta/saree/blouse/shirt trace guides (SwiftUI Paths) | — |
| `ReferenceStudioView` | Pinterest/Insta/camera reference → re-render in chosen fabric | Generate render |
| `RenderView` | Sketch → photoreal Gemini render | Generate, share |
| `VirtualTryOnView` | Customer photo + render → try-on image. DPDP consent captured BEFORE upload; photo purges in 7 days | Link customer, consent, generate, share |
| `CustomerLinkSheet` | Attach a customer to a design mid-flow | Pick customer |
| `ImageInputPicker` | Unified camera / photo library / URL input | — |

### Customers — the CRM (8 views)
| Screen | Purpose | Key actions |
|---|---|---|
| `CustomersListView` | Server-side searchable list | Add, search (name/phone/email) |
| `CustomerFormView` | Contact + WhatsApp # + address + DPDP consents + tags | Create/edit |
| `CustomerDetailView` | The customer hub: header, quick actions, journey timeline, style profile, dates, **spend panel**, orders, measurements, inquiries | WhatsApp, new inquiry, measurements, **Suggest a look (AI)** |
| `CustomerSpendSummaryView` | Lifetime spend, order count, avg, 12-month chart (excludes cancelled/returned) | — |
| `CustomerStyleProfileView` | Style notes, preferences | Edit |
| `CustomerTimelineEventStyling` | Timeline event rendering | — |
| `ImportantDateFormView` | Birthday/anniversary capture | Create |
| `StyleSuggestionsSheet` | Gemini 3-suggestion next-look panel from history | Generate/regenerate |

### Inquiries (2 views)
| Screen | Purpose | Key actions |
|---|---|---|
| `InquiriesListView` | Pre-order funnel (new → … → converted) | Status transitions via `allowedNext` |
| `InquiryFormView` | Occasion, budget, source, notes | Create/edit, convert to order |

### Orders — money + fulfilment (7 views)
| Screen | Purpose | Key actions |
|---|---|---|
| `OrdersListView` | All orders, status filter, **slack badges** (R1) | Open detail |
| `OrderCreateView` | Line items, GST, atomic create via RPC, **event date + buffer + must-finish-by warning** (R1) | Create (race-safe number) |
| `OrderDetailView` | Status machine, items, invoice, **deadline slack row** (R1), **lock row + change orders** (R3), **Notify customer** (WA/Email/SMS), magic link | Advance status, lock the look, apply change order, generate invoice PDF, notify |
| `OrderTimelineView` | Status history | — |
| `PaymentsSectionView` | Advance/balance ledger, record payment, WhatsApp reminder, **Razorpay payment link** | Record, remind, create link |
| `AlterationsSectionView` | Trial → alteration rounds | Log alteration |
| `InvoicePreviewView` | GST invoice PDF (CGST/SGST, GSTIN, customer address) | Share/print |

### Job cards (2 views)
| Screen | Purpose | Key actions |
|---|---|---|
| `JobCardComposerView` | Compose from design + order + measurements; AI Hinglish karigar brief incl. fabric-meters andaaza (R4c) | Generate |
| `JobCardPreviewView` | Hybrid PDF + karigar phone-link panel (R4d): share/regenerate magic link, live progress events | Share/print, share karigar link |

### Important dates (1 view)
| Screen | Purpose | Key actions |
|---|---|---|
| `ImportantDatesListView` | Upcoming birthdays/anniversaries | One-tap WhatsApp greeting |

### Settings (1 view)
| Screen | Purpose | Key actions |
|---|---|---|
| `SettingsView` | Boutique identity (GSTIN, address), GST CSV export, customer CSV import, **Integrations status panel**, sign out | Export, import, edit boutique |

---

## 3. Journeys (cross-screen flows)

### J1 — New customer, first sale (the magic-moment path)
```
InquiriesListView → InquiryFormView (occasion, source, consent)
→ CustomerFormView (contact, WA#, address, DPDP)
→ DesignsListView → "From inspo photo" → ReferenceStudioView (reference + fabric → render)
   or DesignDetailView → SketchCanvasView (template + fabric + strokes) → RenderView
→ VirtualTryOnView (consent → try-on → share)          ← the close
→ OrderCreateView (items, GST) → PaymentsSectionView (advance)
→ JobCardComposerView → PDF to karigar
```

### J2 — Production & delivery
```
OrderDetailView: status pending → confirmed → packed → shipped/delivered
  each transition → "Notify customer" (WA always; Email/SMS when keys set)
AlterationsSectionView: trial → alteration rounds (loop)
PaymentsSectionView: balance → record / WhatsApp reminder / Razorpay link
InvoicePreviewView: GST invoice at handover
```

### J3 — Repeat sale (retention loop)
```
ImportantDatesListView (upcoming occasion)
→ CustomerDetailView → "Suggest a look" (AI, uses history)
→ WhatsApp templated message → yes
→ J1 short-circuit: measurements + style already on file
```

### J4 — Monthly compliance
```
SettingsView → GST CSV export (CGST/SGST/IGST columns) → CA
```

Full narrative walk-throughs: `user-journeys.md`, `customer-journey-3-month.md`.

---

## 4. Department views (who uses what)

Single-owner boutique today — "departments" are hats the owner wears:

| Hat | Screens | Cadence |
|---|---|---|
| Sales / consultation | Inquiries, Designs studio, VTO, Customers | Per walk-in |
| Design studio | Sketch, Reference studio, Render | Per look |
| Production manager | Job cards, Order status, Alterations | Daily |
| Cashier / accounts | Payments, Invoice, GST export, Razorpay links | Per order + monthly |
| Dispatcher | Order fulfilment (pickup/ship/hand-deliver), tracking | Per ready order |
| Marketer | Important dates, AI suggestions, WhatsApp | Weekly |
| Admin | Settings, CSV import, integrations | Rare |

*Multi-role staff (separate karigar/cashier logins with RLS) is deferred —
needs auth rework; see `spec-gaps-waves-1-6.md`.*

---

## 5. Integrations map

| Integration | Transport | Gating | Notes |
|---|---|---|---|
| Supabase (Mumbai) | supabase-swift SDK | Always on | Postgres 17 · 28 migrations · RLS on every boutique-scoped table · Storage buckets (sketches, renders, references, customer-photos, vto-results, karigar-wip) · pg_cron 03:00 IST DPDP purge |
| Karigar link (Edge Function `job-card-view`) | Mobile web, token-capability URL | Always on (verify_jwt off by design) | R4d: GET serves Hinglish job-card page; POST records started/silai-poori/taiyaar (+5MB WIP photo), rate-limited 30/day/card. `ready` zeroes work in slack. |
| Gemini AI | REST, `x-goog-api-key` header | `GEMINI_API_KEY` | `gemini-2.5-flash-image` (render/VTO) + `gemini-2.5-flash` (briefs/suggestions); `AICostMeter` server-side $5/day ceiling |
| WhatsApp | `wa.me` deep links | Consent flag | Owner reviews every message (ADR 0005); `customer.whatsappTarget` |
| SendGrid (email) | REST v3 | `SENDGRID_API_KEY` + `SENDGRID_FROM` | Inert until keys set; consent via `CustomerNotifier` |
| Twilio (SMS) | REST, Basic auth | `TWILIO_SID/AUTH_TOKEN/FROM` | India E.164 normalization; DLT is sender's responsibility |
| Razorpay | REST Payment Links | `RAZORPAY_KEY_ID/SECRET` | Hosted rzp.io links — no on-device card collection, no PCI scope |

All key-gated integrations follow one pattern: `Config.<service>Enabled` →
button visible-but-disabled with the exact missing key named → status panel in
Settings → Integrations. Keys live in gitignored `Secrets.xcconfig`.

Consent architecture: **all customer-outbound sends route through
`CustomerNotifier`** — the single DPDP audit point.

---

## 6. Data spine

```
Boutique 1—* Customer 1—* Order 1—* OrderItem · Order 1—* Payment
Customer 1—* {Inquiry, Design, Measurement, Appointment, ImportantDate, Profile}
Design 1—* DesignRender 1—* DesignTryOn (customer photo, 7-day purge)
Design/Order → JobCard · Order 1—* Alteration
CustomerTimelineEvent = derived client-side (not a table)
```

Key rules (enforced, see CLAUDE.md §3): persist (bucket, path) never signed
URLs · sequence numbers via RPC · multi-row writes atomic via RPC · status
transitions via enum `nextOptions` · money via `Money`/`Formatters.inr`.

---

## 7. Roadmap (agreed direction, not yet built)

**Everything here is iPad-native.** Web admin / storefront are retired from
the roadmap (decision July 2026, reaffirming ADR 0001): the competitive
teardown (`competitive/darzi-ai-teardown.md`) confirmed the CRM layer is
commoditized web territory; the moat is the Pencil studio + Look lifecycle,
which only the iPad delivers. A customer-facing magic-link order page remains
a possible future; no owner-facing web app.

From the CRM-design discussion (`customer-journey-3-month.md` lessons) plus
the competitive teardown:

| # | Feature | Why | Source |
|---|---|---|---|
| R1 ✅ | **`event_date` + slack engine** — SHIPPED July 2026: `OrderSlack` engine (6 verdicts incl. overdue honesty guard), must-finish-by warning at creation, badges on list/detail | One primitive powers R2 and R3; prevents the week-11 late delivery | Journey lesson 1 |
| R2 ✅ | **Exception-first morning board** — SHIPPED July 2026: 3 tiles + slack-sorted needs-you + 5-lane pipeline, per-input honest degradation. (Link-sent-unopened state deferred to R4a.) | The owner's question is "what goes wrong if I don't touch it today" | Morning-board design |
| R3 ✅ | **Lock screen** — SHIPPED July 2026: order_locks + change_orders (DB-append-only), atomic lock_order + apply_change_order RPCs, LockSheet + ledger UI | The Look's one irreversible moment; stops spec disputes and date slips | CRM-design discussion |
| R4a | **Auto-drafted reminders, one-tap approve** — trial/payment/ready messages drafted by status hooks, owner approves in bulk | Darzi AI fires these automatically; we keep review as a feature not a tax | Teardown §4.1 |
| R4b | **PIN-scoped staff roles** — finance hidden from tailor/assistant PINs | Darzi shipped what we deferred; cheaper than full multi-auth RLS rework | Teardown §4.2 |
| R4c ✅ | **Fabric-meters estimate on job cards** — SHIPPED July 2026: andaaza line in the Hinglish brief | Cheap, high daily utility | Teardown §4.3 |
| R4d ✅ | **Karigar phone link** — SHIPPED July 2026: `job-card-view` Edge Function, magic-link page, progress events feed slack | Owner iPad + karigar phone, per surface split decision | Karigar-UX decision |
| R5 | **Fabric inventory** — bolts, codes, meters in/out, issue-to-job-card | Fills the "Fabrics" sidebar slot; feeds real costing + the lock screen's in-stock check | Flow-map gap |
| R6 | **Karigar ledger** — material issued, piece-rate dues, alteration-rate per karigar | Fills production back-of-house; quality metric | Flow-map gap |

Build order: R1 → R2 → R3 → R4 (a/b/c parallelizable) → R5 → R6.
R1 is the dependency for R2 + R3; R4 items are independent absorbs; R5
unblocks the lock screen's fabric-code check but the lock screen ships
without it first (free-text fabric code until inventory exists).

**Watch items** (from the teardown): Darzi AI shipping any sketch/design
tool · pricing going public · an iPad app · a fabric-inventory module.
