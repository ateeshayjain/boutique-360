# Design: Event-date slack engine + fabric-meters estimate + karigar phone link

**Date:** 2026-07-28 · **Status:** approved by owner (this doc formalizes it)
**Roadmap items:** R1 (slack engine), R4c (fabric meters), R4d (karigar link)
**Context docs:** `docs/app-map.md` §7 · `docs/customer-journey-3-month.md`
(lessons 1–2) · `docs/competitive/darzi-ai-teardown.md` §4.3

## Problem

1. Orders tied to a hard event date (wedding, reception) can silently run out
   of time — the "week-11" failure in the journey doc: no buffer between
   planned completion and the event, discovered only at the fitting.
2. Job cards give the karigar no fabric-quantity guidance; owners estimate
   meters by feel.
3. The karigar's only surface is a static PDF on WhatsApp; the owner keys in
   every production status change herself, so app state lags the workshop.

## Goals

- Compute an honest per-order **slack** number and surface it at order
  creation and on order lists/detail (the R2 morning board later re-sorts
  what this ships).
- Add an **AI fabric-meters estimate** to the Hinglish job-card brief.
- Give the karigar a **phone-usable magic-link page** to view the job card
  and report progress — feeding real `work_remaining` into the slack engine.

## Non-goals (YAGNI)

- The morning board itself (R2), the Lock screen (R3), change-orders (R3).
- Karigar login/accounts, karigar payments (R6), fabric inventory (R5).
- Courier-API delivery estimates — delivery days are constants for now.
- Push notifications to the owner on karigar events (timeline shows them;
  notification polish can ride a later wave).

## Design

### Unit 1 — Migration 0028

```sql
alter table public.orders
  add column if not exists event_date date,
  add column if not exists alteration_buffer_days int not null default 7;

alter table public.job_cards
  add column if not exists share_token uuid not null default gen_random_uuid();

create table public.job_card_events (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  job_card_id uuid not null references public.job_cards(id) on delete cascade,
  event text not null check (event in ('started','stitching_done','ready')),
  wip_photo_path text,
  created_at timestamptz not null default now()
);
-- RLS: owner read via boutique_id (standard policy pair);
-- inserts arrive via the Edge Function using service role after token check.
```

New storage bucket `karigar-wip` (private) for WIP photos.

### Unit 2 — `Utilities/OrderSlack.swift` (pure engine)

```swift
enum OrderSlack {
  enum Verdict: Equatable {
    case noEvent                 // event_date nil — slack undefined, never at-risk
    case noPlan                  // event set, no job-card due date — honest "can't compute"
    case late(days: Int)         // slack < 0
    case atRisk(days: Int)       // 0 ≤ slack ≤ 1
    case comfortable(days: Int)  // slack ≥ 2
  }
  static func evaluate(eventDate: Date?, jobCardDue: Date?, jobCardDone: Bool,
                       orderStatus: OrderStatus, fulfillment: FulfillmentMethod?,
                       alterationBufferDays: Int, today: Date,
                       calendar: Calendar = .current) -> Verdict
}
```

- `work_remaining = jobCardDone || order delivered ? 0 : max(0, due − today)`
- `delivery_days = fulfillment == .ship ? 3 : 0` (constant, revisit with data)
- `slack = (event − today) − work_remaining − alterationBufferDays − delivery_days`
- `jobCardDone` derives from job-card completion OR a `ready` karigar event
  (Unit 5) — callers pass the resolved boolean; the engine stays pure.
- Latest-safe-start (for the creation warning) =
  `event − production_days − buffer − delivery`, where production days come
  from the job-card due date when present.
- All-nil inputs degrade to `.noEvent`/`.noPlan` — never a crash, never a
  fake green. Cancelled/returned orders → `.noEvent` (deadline moot).

### Unit 3 — iPad surfacing (R1 scope)

- `OrderCreateView`: optional event-date picker + buffer stepper (default 7).
  If a computed slack is negative at save time, show an inline warning —
  *"Won't fit: needs latest start by ⟨date⟩"* — warn, don't block (owner may
  knowingly accept rush work).
- `OrdersListView` rows + `OrderDetailView` header: slack badge —
  red `.late` / amber `.atRisk` / green `.comfortable` / gray `.noEvent`
  / hollow `.noPlan`. One shared badge view so R2 reuses it.
- Model: `Order.eventDate`, `Order.alterationBufferDays` decoded; NewOrder +
  patch updated; OrderCreateView passes them through the existing atomic RPC
  (RPC gains two pass-through params).

### Unit 4 — R4c fabric-meters estimate

`PromptTemplates.tailorBrief` gains a Hinglish instruction: include an
estimated fabric requirement in meters based on garment type and available
measurements, explicitly marked *"andaaza — cutting se pehle khud check
karo"*. Text-only change + one prompt-builder unit test asserting the
instruction is present. No schema change; the estimate lives inside the
generated brief, not a column.

### Unit 5 — R4d karigar magic-link page

**Surface split:** owner/manager = iPad native app; karigar = phone browser.
No owner-facing web app (July 2026 strategy; ADR 0001).

- **Edge Function `job-card-view`** (Deno, service role):
  - `GET /functions/v1/job-card-view/⟨share_token⟩` → mobile-first HTML:
    design render (signed URL generated server-side), fabric photos,
    measurements table, Hinglish brief, due date. Big type, no JS framework,
    works on low-end Android. First name only — no customer phone/address.
  - `POST .../⟨token⟩/event` with `event` + optional photo (multipart) →
    validates token → inserts `job_card_events` row, stores photo in
    `karigar-wip` bucket. Rate-limited per token (basic: reject >30/day).
- **Sharing:** JobCardPreviewView gains "Share link with karigar" —
  `wa.me` message containing the link (alongside the existing PDF share).
- **iPad feedback:** OrderTimelineView + JobCardPreviewView show
  `job_card_events` (event + time + WIP photo thumbnail). A `ready` event
  sets `jobCardDone = true` for the slack engine (Unit 2).
- **Security model:** the token IS the capability — same trust level as
  forwarding the PDF today. Unguessable UUID; regenerating the token
  revokes old links ("Regenerate link" button in JobCardPreviewView).
  Page contains no PII beyond customer first name.

### Testing

- `OrderSlackTests` (pure): noEvent, noPlan, exact-fit boundary, atRisk at
  slack 0 and 1, late, delivered order zeroes work, ship-vs-pickup 3-day
  delta, cancelled → noEvent, ready-event zeroes work.
- Prompt test: meters instruction present in `tailorBrief` output.
- Codable round-trip: `Order.eventDate` / `alterationBufferDays`,
  `JobCardEvent` decode.
- Edge Function: manual smoke via curl (GET renders, POST inserts, bad
  token 404) — consistent with the repo's no-network-tests policy.

### Error handling

- Engine: total-nil tolerance (above).
- Karigar POST failures → page shows a Hinglish retry message; events are
  append-only so double-taps are harmless (latest event wins for display).
- Owner surfaces load events with the standard loadError-banner pattern.

### Build order

Migration → models → OrderSlack + tests → OrderCreate/list/detail surfacing
→ R4c prompt → Edge Function + sharing + timeline. R4d last: its events
feed an engine that must exist first.
