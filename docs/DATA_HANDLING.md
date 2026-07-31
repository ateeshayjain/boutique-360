# Data Handling — App Store / Play Store disclosure answers

**Last verified:** 2026-07-31 against the shipping code.
**Purpose:** copy-paste-ready answers for Apple's *App Privacy* questionnaire
and Google Play's *Data safety* form.

Two rules for anyone updating this file:

1. **Answer from the code, not from intent.** Every claim below names the file
   or table it rests on. If a flow changes, this file is wrong until someone
   re-checks it.
2. **When Apple's and Play's definitions differ, note both** rather than
   picking the flattering one. They disagree in places, and the store review
   teams check against different rubrics.

A note on who "the user" is: **customers never touch this app.** The only
person who uses it is the boutique owner or their assistant. Customer data is
entered *about* a third party by the boutique. Both stores' forms are written
assuming the person tapping is the data subject, which is not the case here —
where that distinction changes an answer, it is called out.

---

## Apple — App Privacy

### Does the app collect data? **Yes.**

Apple's definition of "collect" includes transmitting data off-device, which
this app does (Supabase, Gemini).

### Data types

| Apple category | Collected | Linked to identity | Used for tracking | Purpose | Evidence |
|---|---|---|---|---|---|
| **Name** | Yes | Yes | No | App Functionality | `customers.name` |
| **Phone Number** | Yes | Yes | No | App Functionality | `customers.phone`, `whatsapp_phone` |
| **Email Address** | Yes | Yes | No | App Functionality | `customers.email` |
| **Physical Address** | Yes | Yes | No | App Functionality | `customers.address` |
| **Other User Contact Info** | No | — | — | — | — |
| **Health & Fitness** | **No** | — | — | — | See "Measurements" note below |
| **Photos or Videos** | Yes | Yes | No | App Functionality | `vto-uploads`, `customer-photos`, `design-*`, `karigar-wip` buckets |
| **Purchases** | Yes | Yes | No | App Functionality | `orders`, `payments`, `order_items` |
| **Financial Info** | **No** | — | — | — | No card/bank data — Razorpay hosts the payment page; nothing is collected on-device |
| **Precise / Coarse Location** | No | — | — | — | No location APIs linked |
| **Contacts** | No | — | — | — | No Contacts framework access |
| **Sensitive Info** | Yes | Yes | No | App Functionality | Customer photos used for virtual try-on (see below) |
| **User Content — Customer Support** | No | — | — | — | — |
| **User Content — Other** | Yes | Yes | No | App Functionality | Design sketches, notes, style preferences |
| **Identifiers — User ID** | Yes | Yes | No | App Functionality | Supabase `auth.uid()` for the boutique staff account |
| **Identifiers — Device ID** | No | — | — | — | — |
| **Usage Data** | No | — | — | — | No analytics SDK is integrated |
| **Diagnostics** | No | — | — | — | `os.Logger` only; nothing leaves the device |

### Tracking: **No.**

The app does not track in Apple's sense — no data is linked to third-party
data for advertising or measurement, no advertising identifier, no data
brokers. **No ATT prompt is required.**

### Two answers that need care

**"Measurements" are not Health & Fitness data.** The app stores garment
measurements (bust, waist, hip, sleeve). These are tailoring dimensions, not
health or fitness metrics, and are not collected from HealthKit or any sensor
— they are typed in by the boutique from a tape measure. Declaring them under
Health & Fitness would be inaccurate. They are declared under **Sensitive
Info / User Content — Other** as body-related personal data.
Evidence: `CustomerMeasurement` in `Models/Measurement.swift`,
`customer_measurements` table (`supabase/migrations/0007_*.sql:20`).

**Customer photos are declared under Sensitive Info, not just Photos.** A
photograph of an identifiable person's body, processed to render clothing onto
them, is more sensitive than the "Photos or Videos" bucket implies. Both are
declared.

---

## Google Play — Data safety

Play asks two questions Apple does not: whether data is **encrypted in
transit**, and whether users can **request deletion**.

| Play data type | Collected | Shared | Processed ephemerally | Optional | Purpose |
|---|---|---|---|---|---|
| Name | Yes | Yes¹ | No | Required | App functionality |
| Email address | Yes | No | No | Optional | App functionality |
| Phone number | Yes | Yes² | No | Required | App functionality |
| Address | Yes | No | No | Optional | App functionality |
| Photos | Yes | Yes³ | No | Optional | App functionality |
| Purchase history | Yes | No | No | Required | App functionality |
| Other personal info (measurements, preferences) | Yes | No | No | Optional | App functionality |
| App activity / interactions | No | — | — | — | — |
| Crash logs / diagnostics | No | — | — | — | — |

¹ Shared with the boutique's chartered accountant via GST CSV export (statutory filing).
² Shared with WhatsApp when the owner sends a message — the owner initiates and reviews every message; `wa.me` deep link, no Business API.
³ Shared with Google Gemini for the single try-on/render request. Google's API terms state image data is not retained after the response.

**Encrypted in transit:** Yes — all Supabase and Gemini traffic is HTTPS.
Disclosed honestly in `SECURITY_REVIEW.md` §4: there is **no certificate
pinning**, so this is standard TLS, not pinned TLS. Play's question asks only
about encryption in transit, which is satisfied.

**Users can request data deletion:** Yes — `docs/privacy-policy.md` commits to
deletion on request, and immediate deletion of a try-on photo "no questions
asked." **Note the operational gap:** this is honoured by the boutique owner
manually; there is no in-app self-service deletion flow, because customers
have no app account. If Play requires a deletion-request *URL*, the boutique's
contact details in the privacy policy serve that purpose and must be filled in
before submission (they are currently placeholders).

---

## Retention (both stores)

| Data class | Retention | Enforced by |
|---|---|---|
| Virtual try-on photo (upload + result) | **7 days**, unless saved to lookbook | `purge_at` column + `purge-expired-tryons` Edge Function, daily `pg_cron` at 21:30 UTC (03:00 IST) |
| Name, contact, measurements, preferences | Duration of the commercial relationship, or until deletion is requested | Manual |
| Order, payment, invoice records | **8 years** | Indian Income Tax Act + GST Act — overrides general retention and a customer deletion request |

The 8-year statutory hold is worth stating to reviewers explicitly: a customer
deletion request **cannot** purge invoice records, because Indian tax law
requires their retention. `docs/privacy-policy.md` says so in plain language.

---

## Third-party processors

| Processor | What it receives | When | Basis |
|---|---|---|---|
| **Supabase** (AWS ap-south-1, Mumbai) | All app data | Always | Hosting; data residency in India |
| **Google Gemini** | One customer photo + prompt (try-on), or a sketch + prompt (render) | Only at the moment of generation | Explicit consent, captured with a timestamp *before* the call |
| **WhatsApp** (via `wa.me` link) | Message text the owner has reviewed | Owner-initiated only | Consent flag on the customer record |
| **SendGrid / Twilio / Razorpay** | Email / phone / payment amount | Only if credentials are configured; disabled by default | Consent flag, enforced centrally in `Services/CustomerNotifier.swift` |

DPDP consent is enforced in `CustomerNotifier`, not at call sites, so there is
a single audit point for every outbound customer message.

---

## Before submission — unresolved

These block an accurate store listing and are **not** resolved by this file:

- [ ] `docs/privacy-policy.md` has placeholder operator name, GSTIN, contact
      email, phone, and effective date. A store submission with `[TO BE FILLED
      IN]` in the privacy policy will be rejected.
- [ ] The privacy policy must be hosted at a public URL for both stores.
- [ ] Confirm Gemini's current API data-retention terms still support the
      "not retained after response" claim above — this was true when written
      and is a vendor term that can change.
- [ ] No end-to-end verification that the 7-day purge actually deletes rows
      and storage objects (see `SECURITY_REVIEW.md` §9). The cron is verified
      to run; the deletion is not verified to happen.
