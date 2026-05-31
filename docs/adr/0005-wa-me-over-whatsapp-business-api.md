# ADR 0005 — `wa.me` deep links instead of WhatsApp Business API

**Date:** 2026-05-26 (Batch A: wire WhatsApp into 5 surfaces)
**Status:** Accepted

---

## Context

The boutique owner's primary customer communication is WhatsApp (verified in the user-journey audit). Several flows in Boutique 360 should "send a WhatsApp" — payment reminders, order-ready notifications, birthday/anniversary greetings, sharing AI renders.

Two paths to ship this:

1. **WhatsApp Business API (BSP-mediated)** — official API from Meta, requires:
   - Approval as a verified business
   - Working with a BSP (Business Solution Provider) — Gupshup, Twilio, AiSensy, etc.
   - Per-message fees (~₹0.30-0.65 per session message, ~₹0.85 per template)
   - Template approval for any business-initiated message
   - Webhook infrastructure for inbound messages

2. **`wa.me` deep links** — universal URL format `https://wa.me/<phone>?text=<message>` that opens WhatsApp pre-filled with a draft. Owner reviews + hits send manually.

---

## Decision

Use **`wa.me` deep links via SwiftUI ShareLink / a thin helper (`WhatsAppShareHelper`)**.

Specifically:
- Construct URLs via `URLComponents` so emoji/newline encoding is automatic
- Strip non-digits + prepend `91` (India country code) if missing
- Use the universal `wa.me` host (not `whatsapp://`) so we don't need `LSApplicationQueriesSchemes` in Info.plist
- Owner always sees the draft before sending — message is editable in WhatsApp

---

## Consequences

### What becomes easier
- **Zero infrastructure** — no webhook server, no BSP account, no template approval queue, no API rate limits to manage
- **Zero per-message cost** — owner's existing WhatsApp account sends the message; no per-message billing
- **Personal tone preserved** — owner writes / edits the message before sending. Customers receive what feels like a personal text, not a templated business notification
- **No template-approval delays** — when we want a new message style, we change Swift code and ship. With Business API, every template needs Meta approval (24-72h)
- **DPDP-friendly** — we don't transmit the customer's phone or message body to a third-party BSP; everything stays between iOS, our app, and the boutique owner's WhatsApp account
- **Works during outages of our own backend** — the message construction happens client-side; doesn't need Supabase up

### What becomes harder
- **Cannot send templated bulk messages** — every message requires owner tapping send. For a single-boutique pilot this is the right trade-off; for a multi-boutique SaaS where automation matters, Business API becomes necessary.
- **No delivery / read receipts in our system** — we don't know if/when the message landed. We trust the owner's WhatsApp to handle this.
- **No inbound message handling** — customers replying go to the owner's WhatsApp directly, not into our app. (This is fine — owner manages the conversation there.)
- **The link only works if WhatsApp is installed** — `wa.me` falls back to web.whatsapp.com in a browser, which is broken for many users. We rely on the universal-install rate of WhatsApp in India (>95% smartphone penetration).

### What becomes impossible (without adopting Business API)
- **Automated "your order is ready" send-on-status-change** — these go via the owner manually. If the owner is away, no message goes out automatically.
- **Customer messaging analytics** (open rates, response times) — we have none
- **Multi-boutique broadcast** — when SaaS happens, "send all our customers a Diwali sale message" requires Business API

---

## Alternatives considered

### WhatsApp Business API via Gupshup / Twilio / AiSensy
- Pro: automation, broadcast, analytics, delivery receipts
- Con: Cost (~₹0.30-0.85 per message at scale), template approval workflow, webhook server to operate, formal-tone messaging that feels less personal
- **Why rejected for now:** single-boutique pilot doesn't need automation. The cost-per-message + ops complexity isn't paying for itself yet.

### SMS via TextLocal / MSG91
- Pro: India-native, cheap (~₹0.20/message)
- Con: customers don't read SMS anymore; lower open rates; no rich media (images, PDFs); regulatory layer (DLT registration)
- **Why rejected:** customers expect WhatsApp from a boutique. SMS feels like a bank notification.

### Email
- Pro: rich content, free
- Con: customers don't check email for boutique communications; festive collection updates land in promotions tab
- **Why rejected:** wrong channel for this audience

### `whatsapp://` URL scheme (instead of `wa.me`)
- Pro: opens the app directly, no web fallback
- Con: requires `LSApplicationQueriesSchemes` Info.plist entry to even check `canOpenURL`; iOS may prompt user; doesn't degrade gracefully
- **Why rejected:** `wa.me` is the documented modern path; works in browsers too

---

## Migration path (when Business API becomes worth it)

The trigger for re-evaluating this decision is **when we onboard the 5th boutique** (multi-tenant SaaS economics start working):

1. Add a BSP integration as a new Service module (`WhatsAppBusinessAPIService`)
2. Keep `WhatsAppShareHelper` for personal/owner-driven messages (don't remove it)
3. Use Business API for automated nudges (overdue payment auto-reminder, order-ready auto-send when status changes to `.delivered`)
4. Owner toggles auto-vs-manual per message type in Settings
5. The Postgres schema needs a `whatsapp_messages` audit table for delivery + cost tracking

Estimated effort: 1 week including template approvals.

---

## Related

- `Utilities/WhatsAppShareHelper.swift` — implementation
- `docs/user-journeys.md` Journey 7 (proactive outreach) + Journey 3 (order confirmation)
- `docs/user-flows.md` Flow 5 (error surfacing pipeline — covers WhatsApp send errors)
