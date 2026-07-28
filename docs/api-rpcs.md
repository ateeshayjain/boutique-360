# Postgres RPCs — Reference

All RPCs are `security invoker` — they run with the caller's RLS context. Callers must be authenticated via Supabase Auth and have a matching `staff_users` row.

---

## `next_sequence_value(p_boutique_id uuid, p_sequence_name text) returns bigint`

Race-safe monotonic counter, scoped to `(boutique_id, sequence_name)`. Used for order numbers, job card numbers, inquiry numbers.

```sql
-- Owns: boutique_sequences(boutique_id, name, next_value)
-- Locks the row, increments, returns the new value.
```

**Swift call**:
```swift
struct P: Encodable { let p_boutique_id: UUID; let p_sequence_name: String }
let next: Int64 = try await SupabaseService.client
    .rpc("next_sequence_value", params: P(p_boutique_id: bid, p_sequence_name: "orders-2026"))
    .execute().value
return "BTQ-2026-\(String(format: "%04d", next))"
```

Used by:
- `OrdersService.generateOrderNumber`
- `JobCardsService.generateJobNumber`
- `InquiriesService.generateInquiryNumber`

---

## `create_order_with_items(p_order jsonb, p_items jsonb, p_source_inquiry_id uuid) returns orders`

Atomic order creation. Single transaction: order header insert + line items inserts + optional inquiry link update. Any failure rolls back the whole thing.

**Why**: previously 3 separate client calls could leave orphan order headers if the items insert failed.

**Swift call**:
```swift
struct RPCParams: Encodable {
    let p_order: NewOrder
    let p_items: [LineDraftEncodable]
    let p_source_inquiry_id: UUID?
}
return try await SupabaseService.client
    .rpc("create_order_with_items", params: params)
    .execute().value
```

Used by: `OrdersService.create`.

---

## `next_alteration_round(p_order_id uuid) returns int`

Race-safe round number for a given order's alterations. `FOR UPDATE` lock inside.

**Swift call**:
```swift
struct P: Encodable { let p_order_id: UUID }
let next: Int = try await SupabaseService.client
    .rpc("next_alteration_round", params: P(p_order_id: orderId))
    .execute().value
```

Used by: `AlterationsService.nextRoundNumber`.

---

## `current_boutique_id() returns uuid`

Internal helper used by RLS policies. Returns the boutique_id of the current authenticated user, by joining `auth.uid()` → `staff_users.boutique_id`.

Defined in `0017_rls_helpers.sql`. Cached for the session.

```sql
create or replace function current_boutique_id()
returns uuid
language sql stable
as $$
  select boutique_id from public.staff_users where user_id = auth.uid() limit 1;
$$;
```

Every RLS policy on a boutique-scoped table uses:
```sql
create policy "boutique_scoped" on public.<table>
  using (boutique_id = current_boutique_id());
```

---

## Triggers

### `trg_staff_user_bootstrap` on `auth.users` insert

Creates a default `staff_users` row when a new Supabase Auth user signs up. Maps them to the first boutique in the system (single-tenant pilot pattern). When multi-tenant, this becomes an invite-flow.

Defined in `0020_rls_subquery_fix_and_staff_bootstrap.sql`.

---

## Edge Functions

### `purge-expired-tryons`

Triggered: pg_cron daily at 21:00 UTC (02:30 IST).

Behavior:
1. Select `design_tryons` where `purge_at < now()` AND `saved_to_lookbook = false`
2. Delete storage objects in `customer-photos` + `vto-results` buckets
3. Delete DB rows
4. Return `{purged: N, storage_errors: [...], db_error: null}` for logs

Auth: `verify_jwt = false`; pg_cron invokes via service role internally.

---

## How to add a new RPC

1. Write SQL in a new migration: `supabase/migrations/00NN_purpose.sql`
2. Apply via `mcp__supabase__apply_migration`
3. Add a Swift wrapper in the matching `Service`:
   ```swift
   struct P: Encodable { /* params */ }
   let result: <Type> = try await SupabaseService.client
       .rpc("<rpc_name>", params: P(...))
       .execute().value
   ```
4. Document here

---

## Edge Function HTTP endpoints (not RPCs, documented here for one-stop API reference)

### `job-card-view` (R4d — karigar magic link; verify_jwt OFF, token = capability)

| Method + path | Body | Returns |
|---|---|---|
| `GET /functions/v1/job-card-view/⟨share_token⟩` | — | 200 mobile HTML (Hinglish job card: image, naap, brief, status buttons); 404 bad token |
| `POST /functions/v1/job-card-view/⟨share_token⟩/event` | multipart: `event` ∈ started·stitching_done·ready, optional `photo` (≤5 MB jpeg/png) | 303 back to GET (PRG); 400 bad event; 413/415 photo limits; 429 >30 events/24h/card |

Token rotation: `job_cards.share_token` regenerated from JobCardPreviewView
(old links die). Events land in `job_card_events` (RLS: owner read; inserts
via service role inside the function only).

Note on `create_order_with_items` (migration 0028): the order-header insert
uses an explicit column list + `coalesce` per defaulted column — do NOT
revert to `insert … select * from jsonb_populate_record(...)`; that form
writes NULLs for absent keys and bypasses column defaults.

## R3 RPCs (migration 0029)

### `lock_order(p_lock jsonb) returns order_locks`
Atomic: inserts the lock row AND patches `orders.design_id`. Server-enforced:
order must exist, payload boutique must match the order's, status ∈
{pending, confirmed}. `unique(order_id)` → raced double-lock is a clean
23505 (client treats as already-locked success).

### `apply_change_order(p_order_id, p_description, p_price_delta, p_new_event_date) returns change_orders`
Atomic: inserts the append-only CO row + updates the order's
subtotal/gst/total/event_date. Server-enforced: order must be LOCKED;
`subtotal + delta ≥ 0`; GST recomputed at the order's effective rate
(gst/subtotal; ₹0-subtotal orders → rate 0, accepted limitation); exact
invariant `total = subtotal + gst + shipping` (reuses the rounded GST).
`change_orders` has select+insert policies only — append-only at the DB.

---

## Naming conventions

| Convention | Example |
|---|---|
| Function name | snake_case verb_object | `create_order_with_items` |
| Parameter prefix | `p_` | `p_boutique_id` |
| Security model | `security invoker` always (never definer unless explicitly needed) | |
| Return type | named composite where possible (e.g., `returns public.orders`) | |
| Error surfacing | raise descriptive exceptions; PostgREST surfaces them cleanly | |
