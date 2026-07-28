# Design: Lock the look + change-orders (R3)

**Date:** 2026-07-28 · **Status:** approved by owner (this doc formalizes it)
**Roadmap item:** R3 · **Depends on:** R1 slack engine (shipped), R2 board
(shipped). Fabric-stock validation deliberately deferred to R5 — fabric code
is free text here.
**Context docs:** `docs/app-map.md` §7 · CRM-design discussion (the Look
lifecycle's "one irreversible moment").

## Problem

Before the lock, iteration is free. After a sale closes there is no frozen
contract: "but you said you'd add sleeves" disputes, silently re-negotiated
prices, and event dates that drift without a record. The two classic
failures the journey doc surfaced.

## Goals

- One deliberate **lock action** on an order that freezes the spec: design +
  render, fabric, pinned measurement snapshot, price breakup, event-date
  plan, advance.
- Post-lock spec changes only via **append-only change-orders** with price/
  date deltas, applied atomically.
- Close the Look thread structurally: orders gain `design_id`.

## Non-goals (YAGNI)

- Lock PDF export / customer-facing confirmation.
- Editing or voiding change orders (append-only; mistakes are corrected by a
  counter-CO).
- Fabric-stock validation (R5) — `fabric_code` is free text.
- Locking flows for inquiries/designs themselves (the lock is an order-level
  act).
- Enforcing lock on line-item edits (no item-edit UI exists today; the
  enforced surfaces are event date, buffer, and totals).

## Design

### Unit 1 — Migration 0030

(0029 is reserved in case a hotfix lands first; use the next free number.)

```sql
alter table public.orders
  add column if not exists design_id uuid references public.designs(id) on delete set null;

create table if not exists public.order_locks (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  order_id uuid not null unique references public.orders(id) on delete cascade,
  design_id uuid references public.designs(id) on delete set null,
  render_image_path text,
  fabric_code text,
  fabric_description text,
  measurement_id uuid references public.customer_measurements(id) on delete set null,
  price_breakup jsonb,               -- {"fabric": n, "work": n, "other": n}
  event_date date,                   -- frozen copy at lock time
  alteration_buffer_days int,        -- frozen copy
  must_finish_by date,               -- frozen computed copy
  advance_amount numeric not null,
  rush_accepted boolean not null default false,
  locked_at timestamptz not null default now()
);
alter table public.order_locks enable row level security;
-- standard policy pair (authenticated via app.boutique_id, service_role all)

create table if not exists public.change_orders (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques(id) on delete cascade,
  order_id uuid not null references public.orders(id) on delete cascade,
  description text not null,
  price_delta numeric not null default 0,   -- pre-GST delta to subtotal; may be negative
  new_event_date date,                      -- null = unchanged
  created_at timestamptz not null default now()
);
create index if not exists change_orders_order_idx on public.change_orders(order_id, created_at);
alter table public.change_orders enable row level security;
-- standard policy pair

-- Atomic CO application: insert CO + retarget order totals/event date.
-- GST recomputed at the ORDER'S EFFECTIVE RATE = gst_amount / nullif(subtotal, 0)
-- (orders store amounts, not a rate; zero-subtotal orders use rate 0).
create or replace function public.apply_change_order(
  p_order_id uuid,
  p_description text,
  p_price_delta numeric default 0,
  p_new_event_date date default null
) returns public.change_orders
language plpgsql
as $$
declare
  v_order public.orders;
  v_rate numeric;
  v_co public.change_orders;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'order % not found', p_order_id; end if;

  v_rate := case when v_order.subtotal > 0
                 then v_order.gst_amount / v_order.subtotal else 0 end;

  insert into public.change_orders (boutique_id, order_id, description, price_delta, new_event_date)
  values (v_order.boutique_id, p_order_id, p_description, p_price_delta, p_new_event_date)
  returning * into v_co;

  update public.orders
     set subtotal   = subtotal + p_price_delta,
         gst_amount = round((subtotal + p_price_delta) * v_rate, 2),
         total      = round((subtotal + p_price_delta) * (1 + v_rate), 2)
                      + coalesce(shipping, 0),
         event_date = coalesce(p_new_event_date, event_date),
         updated_at = now()
   where id = p_order_id;

  return v_co;
end;
$$;
```

Note the update reads `subtotal` pre-update inside one statement (Postgres
uses the row's old values on the right-hand side — all three expressions see
the pre-CO subtotal, which is the intent).

### Unit 2 — Models

- `Order.designId: UUID?` (+ CodingKey `design_id`; NewOrder + create path
  pass nil — design linking happens at lock time or later).
- `OrderLock` struct mirroring the table (Codable; `price_breakup` as
  `PriceBreakup { fabric, work, other: Double }`).
- `ChangeOrder` struct mirroring the table.
- `NewOrderLock` Encodable for insert.

### Unit 3 — `Utilities/LockGate.swift` (pure, tested)

```swift
enum LockGate {
    enum Blocker: Equatable {
        case noAdvance                       // no captured payment
        case eventInsideBuffer(mustFinishBy: Date)  // must_finish_by < today, rush not accepted
        case breakupMismatch(sum: Double, subtotal: Double)
    }
    /// Empty array = lockable. Order of checks: advance → event → breakup.
    static func blockers(advancePaid: Double,
                         eventDate: Date?, fulfillment: FulfillmentMethod?,
                         alterationBufferDays: Int, rushAccepted: Bool,
                         breakup: (fabric: Double, work: Double, other: Double)?,
                         subtotal: Double,
                         today: Date, calendar: Calendar = .current) -> [Blocker]
}
```

Rules:
- `advancePaid <= 0` → `.noAdvance`. (Advance = sum of captured payments —
  the existing `PaymentsService` captured semantics.)
- Event set AND `OrderSlack.mustFinishBy(...) < startOfDay(today)` AND
  `!rushAccepted` → `.eventInsideBuffer`. Rush-accepted lets the owner lock
  anyway — recorded on the lock row.
- Breakup provided AND `!Money.equalAtPaise(fabric+work+other, subtotal)` →
  `.breakupMismatch`. Breakup is optional (nil = skip the check); when
  provided it must reconcile.
- Pure function; never throws.

### Unit 4 — `Services/OrderLocksService.swift`

```swift
enum OrderLocksService {
    static func get(orderId: UUID, boutiqueId: UUID) async throws -> OrderLock?
    static func lock(_ input: NewOrderLock) async throws -> OrderLock   // plain insert; unique(order_id) makes double-lock a DB error
    static func changeOrders(orderId: UUID, boutiqueId: UUID) async throws -> [ChangeOrder]
    static func applyChangeOrder(orderId: UUID, description: String,
                                 priceDelta: Double, newEventDate: String?) async throws -> ChangeOrder
    // applyChangeOrder calls the apply_change_order RPC.
}
```

Also: `DesignsService.list(customerId:)` already exists for the design
picker; latest render via `DesignRendersService.listForDesign` filtered
`status == .done` first (same as VirtualTryOnView).

### Unit 5 — UI

**`Features/Orders/LockSheet.swift`** — presented from OrderDetailView
("Lock the look" button, visible only while no lock row exists):
- Design picker: customer's designs (`DesignsService.list(customerId:)`),
  optional ("No design — off-rack"). Picking one shows its latest done
  render (signed URL) and stores `design_id` + `render_image_path` on the
  lock AND patches `orders.design_id` (single-column update via
  `OrdersService`).
- Fabric: code (free text) + description.
- Measurement pin: picker over the customer's `CustomerMeasurement`
  snapshots (label: garmentType + `takenAt` date), defaulting to the most
  recent. Optional when the customer has none.
- Price breakup: three currency fields (fabric/work/other) with a live
  sum-vs-subtotal check line. Optional — "skip breakup" leaves nil.
- Event plan recap (read-only from the order): event date, buffer,
  computed must-finish-by, current slack verdict via `SlackBadge`.
  If must-finish-by is past: red warning + "Accept rush and lock anyway"
  toggle (sets `rush_accepted`).
- Advance line: captured-payments sum (via
  `PaymentsService.capturedSumsForOrders([orderId])`); the Lock button is
  disabled while `LockGate.blockers(...)` is non-empty, with the first
  blocker's message shown beneath.
- Lock action: insert `order_locks` row; on unique-violation (double-tap /
  raced lock) reload and show the existing lock (treat as success).

**OrderDetailView changes:**
- Summary section: when locked, a "Locked" `LabeledContent` row
  (lock icon + `locked_at` date) that navigates to the lock summary.
- When locked, the R1 "Event deadline" affordances become read-only and a
  "Change order" button appears.
- **`LockSummarySheet`** (same file or sibling): read-only lock fields
  (design render thumbnail, fabric, pinned measurement date, breakup,
  frozen event plan, advance, rush flag) + change-order history list
  (description, ±₹, new date, timestamp) + "Add change order" form
  (description required, ₹ delta default 0, optional new event date) →
  `applyChangeOrder`. After applying, refresh the order (totals/event date
  changed) via the existing `.orderDidChange` notification.

### Testing

- `LockGateTests` (pure): no-advance blocks; advance passes; event past
  must-finish-by blocks unless rushAccepted; boundary must-finish-by ==
  today passes; breakup mismatch blocks; nil breakup skips; blocker order.
- Decode tests: `OrderLock` (incl. null design/measurement/breakup),
  `ChangeOrder` (null new_event_date), `Order.designId` absent-key
  tolerance (custom init already exists — decodeIfPresent).
- CO math is server-side: verified by rollback-wrapped live smoke via MCP
  (create order → apply CO with delta + new date → assert new subtotal/
  gst/total/event_date → rollback), same technique as 0028's RPC repair.
- GST recompute rule tested in the smoke: order with 5% effective rate,
  delta +1000 → gst +50, total +1050.

### Error handling

- Lock insert failures surface via the sheet's inline error (house
  pattern); unique-violation treated as already-locked success.
- `apply_change_order` exceptions surface cleanly through PostgREST →
  inline error in the CO form.
- Lock fetch failure on OrderDetailView → treat as unlocked but suppress
  the "Lock the look" button and show the standard load-error banner
  (never offer locking on unknown state).

### Build order

Migration + RPC (with live smoke) → models + decode tests → LockGate +
tests → OrderLocksService → LockSheet → OrderDetailView integration +
LockSummarySheet + CO form → docs.
