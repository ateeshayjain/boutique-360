# Spec Coverage — Waves 1–6 (June 2026)

Closes the gaps identified in the "Elite Boutique Digitization Platform" spec
coverage matrix. Six waves, six commits on `feat/spec-gaps`, merged to `main`
as `--no-ff` merge commit so the work reads as one landing in
`git log --first-parent` and can be reverted with `git revert -m 1 <merge>`.

## Wave 1 — Structured address + separate WhatsApp #

**Why:** Real boutiques routinely have a landline/billing phone different from
the family WhatsApp number — and invoices need the billing phone, not the WA
one. The `address_json` JSONB column had existed in `customers` since migration
0006; it just wasn't exposed in the Swift model.

**What shipped:**
- Migration `0027_customer_whatsapp_phone.sql` — adds nullable `whatsapp_phone text`.
- `Address` struct (line1/line2/city/state/pin/country) decoded from the
  existing `address_json` JSONB column.
- `Customer.whatsappTarget` computed: prefers `whatsapp_phone`, falls back to
  `phone`. **Existing customers keep working with no edit needed.**
- `CustomerFormView`: new Address section, "WhatsApp same as phone" toggle.
- 4 WA-share call sites switched from `customer.phone` → `customer.whatsappTarget`.
- Invoice PDF wires `customer.address.multiLine` + billing phone (not WA).

## Wave 2 — Per-customer spend report

**Why:** Boutiques need a one-glance answer to "is this a VIP" — lifetime spend,
order count, average. Builds confidence in pricing decisions and gift comps.

**What shipped:**
- `CustomerSpend.summarize`: pure aggregator over `[Order]`.
  - **Definition:** Spend = total of orders NOT in `cancelled` or `returned`.
    "Billed and kept" — won't inflate VIP status from cancelled-then-redone
    orders.
  - 12-month buckets keyed by `placedAt ?? createdAt`. Months with no orders
    emit `total: 0` so the chart has a continuous timeline.
- `CustomerSpendSummaryView`: 3 KPI tiles + Swift Charts bar chart + first/last
  order footnote.
- Inserted in `CustomerDetailView` between dates + orders. **Zero new DB calls**
  — operates on the orders array the parent already loaded.
- Tests: empty / cancelled-excluded / 12-month-continuity / out-of-window cases
  (4/4 pass).

## Wave 3 — Email + SMS scaffold (SendGrid + Twilio)

**Why:** WhatsApp link-flow doesn't cover every customer. Some boutiques want
direct programmatic delivery; some customers prefer email for order-ready notices.

**What shipped, INERT until keys are set:**
- `Config.emailEnabled`, `Config.smsEnabled` flags. Same pattern as
  `Config.aiEnabled` (Gemini).
- `SendGridClient`: minimal v3 `mail/send`. Tracking disabled by default for
  DPDP minimization. HTML body + auto plain-text fallback.
- `TwilioClient`: minimal `Messages.json` POST with HTTP Basic auth +
  India-first E.164 normalization (10-digit / 0-prefixed / 91-prefixed all
  coerce; foreign +numbers pass through). 7/7 tests pass.
- `CustomerNotifier`: unified envelope — **DPDP consent enforced in one place,
  not per-call-site**. `orderReadyPlan(for:)` builds WA + Email + SMS plans
  simultaneously; channels not consented / not configured are simply omitted.
- `OrderDetailView`: new "Notify customer" section replaces the WhatsApp-only
  section. Each channel button independently gated; unconfigured channels show
  a discoverable hint (`"Email — add SENDGRID_API_KEY to enable"`) instead of
  vanishing.
- `SettingsView`: new "Integrations" section shows status of AI / Email / SMS /
  Razorpay with the exact key name to set in `Secrets.xcconfig`.

**To enable:** add to `ipad/Boutique360/Configuration/Secrets.xcconfig`:
```
SENDGRID_API_KEY = SG.xxxxxxxxxxxxxxx
SENDGRID_FROM = Boutique Name <hello@boutique.in>
TWILIO_SID = ACxxxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_AUTH_TOKEN = xxxxxxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_FROM = +12025551234
```

## Wave 4 — Razorpay payment-link scaffold

**Why:** Spec wants live payment processing. Boutique360 doesn't do on-device
card collection (that requires Razorpay's iOS SDK + full PCI scope). Hosted
**Payment Links** are the right answer for boutique-style remote payment
collection: UPI/card/netbanking/wallet all work, customer opens an rzp.io URL.

**What shipped, INERT until keys are set:**
- `RazorpayClient.createPaymentLink`: POST `/v1/payment_links` with HTTP Basic.
  Returns `short_url` + `plink_xxx` id for reconciliation. Amount in paise,
  expiry 14d, partial payments off, customer pre-filled.
- `PaymentsSectionView`: when balance > 0 and Razorpay is configured, shows
  "Create payment link". Generated URL is shown inline (copy-able) and — if
  the customer consented to WhatsApp — auto-handed to `wa.me` with a templated
  message.
- Hidden when unconfigured; discoverable hint when balance is zero.

**To enable:**
```
RAZORPAY_KEY_ID = rzp_test_xxxxxxxxxxxxxxx
RAZORPAY_KEY_SECRET = xxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Multi-tenant note: secret stays on-device because Boutique360 is
single-tenant-per-install. For SaaS this code would move to a Supabase
Edge Function so the secret never reaches a client device.

## Wave 5 — Garment templates on canvas

**Why:** New designers need a tracing guide before sketching a kurta from
scratch.

**What shipped:**
- `GarmentTemplate` enum: kurta / saree drape / blouse / shirt as SwiftUI
  `Path` drawn into unit rects. **No PNGs to bundle** — scales to any canvas
  size, no Retina/locale concerns. Symmetrical so the mid-line works.
- `GarmentTemplateOverlay`: faint dashed stroke. `allowsHitTesting(false)` so
  it never blocks strokes or fabric drags.
- `SketchCanvasView`: bottom-bar Menu picks "No template" or one of four. Lives
  below fabric overlays + strokes in the existing ZStack.
- `composeRaster()` bakes the template at alpha 0.25 into the 1024×1024 PNG so
  the Gemini renderer sees the silhouette being traced — nudges the AI, doesn't
  dominate strokes.

## Wave 6 — AI style suggestions from customer history

**Why:** Designer wants the next consultation prep on tap — "what should
Priya wear to her sister's haldi?"

**What shipped:**
- `GeminiService.suggestStyles` / `PromptTemplates.styleSuggestions`: text
  round-trip on `gemini-2.5-flash` (already wired with AICostMeter throttling).
  Tight prompt: exactly 3 numbered lines, each silhouette + fabric + occasion
  + signature detail.
- `parseSuggestionLines`: regex strip of numbered/bullet prefixes (tolerant to
  `"1."`, `"1)"`, `"- "`, `"•"`, `"*"`) + first-3 cap so a chatty trailing
  sentence doesn't pollute the cards.
- `StyleSuggestionsSheet`: shows the context being sent (occasions, garments,
  upcoming occasion) so the designer can sanity-check what the model saw.
  Generate / Regenerate. Error surfaced inline.
- `CustomerDetailView`: new "Suggest a look" quick action **only when
  `Config.aiEnabled`**. Uses already-loaded inquiries + the nearest upcoming
  important date as the signal — zero new DB calls.

## What's not in this branch

| Spec item | Reason |
|---|---|
| Multi-role staff (owner/staff) | Needs auth rework + RLS rewrite. Worth its own spec→plan loop. |
| Hosted live-deploy URL | Not applicable. Native iPad app per ADR 0001 — there's no web URL to host. Delivery is Build & Run from Xcode. |
| WhatsApp Business API auto-send | Deliberately not built (ADR 0005). Owner-reviewed `wa.me` link flow stays. |
| Twilio SMS to Indian numbers requires DLT registration | Twilio doesn't validate that — sender's responsibility. |

## Verification

- All builds: ✅ green on `iOS Simulator` Debug configuration.
- New tests: ✅ 11/11 pass (`CustomerSpendTests` 4/4, `TwilioNormalizeTests` 7/7).
- Migration 0027: ✅ applied to live Supabase project `tdnwdlrkbrtoxjzcgusg`.
- Branch: `feat/spec-gaps` merged to `main` via `--no-ff`.

## Setup checklist for a new install

1. `xcodegen generate` in `ipad/`
2. Copy `ipad/Boutique360/Configuration/Secrets.xcconfig.example` → `Secrets.xcconfig` (gitignored) and fill in whichever integrations you want live.
3. Build & Run from Xcode.
4. Settings → Integrations shows green checkmarks for whatever you configured.
