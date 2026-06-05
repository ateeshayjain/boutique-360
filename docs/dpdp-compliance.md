# DPDP Act 2023 — Compliance Posture

The Digital Personal Data Protection Act 2023 ("DPDP Act") regulates how Indian businesses handle personal data of Indian data principals. Boutique 360 processes customer phone numbers, names, addresses, photos (VTO), and event dates — all of which are personal data under the Act.

This document is a **practical posture statement**, not legal advice. The boutique owner should verify with a CA / lawyer before commercial deploy at scale.

---

## What we collect

| Data class | Where stored | DPDP category |
|---|---|---|
| Name, phone, email, DOB | Postgres `customers` table | Personal data |
| Style preferences (persona, body type, colors) | `customer_profiles` table | Personal data (preferences) |
| Measurements (bust, waist, hip…) | `customer_measurements` table | Personal data (physical) |
| WhatsApp consent flag | `customers.consent_whatsapp` (boolean + timestamp) | Consent record |
| VTO photo of customer | `customer-photos` Supabase Storage bucket (private) | **Sensitive personal data — biometric** |
| VTO result image (composited) | `vto-results` Supabase Storage bucket (public, watermarked) | Personal data |
| Important dates (birthday, anniversary) | `important_dates` table | Personal data |

---

## Legal basis (per DPDP Section 4)

We rely on **consent** (Section 6) for every data class above. Specifically:

1. **WhatsApp consent**: explicit boolean toggle in CustomerFormView. Stored as `consent_whatsapp` + `consent_whatsapp_at` timestamp (planned column — currently boolean only). Owner records this verbally and toggles in the app. Customer must verbally agree before owner toggles.

2. **VTO consent (Section 6 + Section 12 minor protections)**: dedicated consent UI in VirtualTryOnView. Owner cannot proceed unless:
   - The customer's name is typed into the "signer name" field
   - The consent toggle is on
   - The consent timestamp is captured at toggle time (NOT at API call time)

The consent record persists in `design_tryons.customer_consent_signed_at` (timestamptz). Audit trail = the row itself.

3. **Measurement + general profile data**: implicit consent via the act of providing the data in person. Owner should verbally confirm "is it OK if I save these measurements for next time?" before entering.

---

## Rights of the data principal (Sections 11–13)

| Right | How fulfilled |
|---|---|
| Right to **access** | Owner can show the customer their record from CustomerDetailView. (Future: export-personal-data button.) |
| Right to **correction** | CustomerFormView edit mode. Owner can update in customer's presence. |
| Right to **erasure** | `softDelete(customer)` exists (sets `deleted_at`). Hard delete via Supabase admin only — currently manual. (Future: in-app "delete customer" with cascading purge of measurements + photos.) |
| Right to **grievance redress** | Out of band — customer messages owner on WhatsApp. |
| Right to **nominate** (in case of incapacity) | Not implemented. Owner-mediated. |

---

## Retention (Section 8(7))

| Data | Retention | Mechanism |
|---|---|---|
| Customer photo (VTO upload) | **7 days unless saved to lookbook** | `purge_at` column + `purge-expired-tryons` Edge Function on daily cron at 02:30 IST |
| VTO result image | Same 7-day window if linked to a purged tryon row | Edge Function deletes both objects in one pass |
| Measurements, profile, contact | Indefinite (commercial relationship is ongoing) | Manual delete on customer request |
| Orders, invoices, GST records | **8 years** (per GST law, supersedes DPDP) | Indefinite — required by Income Tax Act and GST Act |

The 7-day customer-photo window is a self-imposed limit — strictly stricter than DPDP requires. It exists because biometric data (customer's face) is sensitive and the boutique has no business holding it beyond the immediate VTO use case.

---

## Where biometric/sensitive data physically lives

- **Region**: Supabase `ap-south-1` (Mumbai). Critical for DPDP "data fiduciary" obligations on cross-border transfer (Section 16) — keeps data in India by default.
- **Gemini API calls**: customer photo briefly sent to Google's `generativelanguage.googleapis.com` for VTO. This crosses the border. Mitigations:
  - Gemini API does not retain image data after the response (Google's API ToS)
  - The owner explicitly captures consent that includes this processing
  - The result is composited and returned within ~30s; nothing else is stored at Google

The verbal consent the owner records should specifically mention "your photo will be processed by Google's AI for the virtual try-on." This is **owner training**, not an app control.

---

## Security controls

| Control | Implementation |
|---|---|
| Session tokens | Keychain (kSecAttrAccessibleAfterFirstUnlock) — bound to device passcode |
| Network | TLS 1.3 to Supabase + Gemini |
| RLS | All boutique-scoped tables filter by `boutique_id = current_boutique_id()` (subquery against `staff_users`) |
| Client-side filter | Every query *also* includes `.eq("boutique_id", value: bid)` as belt-and-braces |
| Storage permissions | Private buckets accessible only via short-lived (1hr) signed URLs |
| Secrets | `Secrets.xcconfig` gitignored; commits hooks (planned) would block API keys |

---

## Breach response posture (Section 8(6))

Boutique 360 is a small-fleet app. Breach detection relies on:

1. Supabase audit logs (RLS denials, abnormal query patterns)
2. Manual review of staff_users sign-in events
3. Gemini API quota alerts (anomalous usage = potential token leak)

In a breach scenario:
1. Owner notifies Data Protection Board within 72 hours (planned process — currently no template)
2. Owner notifies affected customers via WhatsApp
3. Owner rotates Supabase service role key + Gemini API key
4. Owner revokes all sessions via Supabase admin UI

A formal breach runbook should be added to `docs/runbooks/` before public commercial deployment.

---

## Open items / known gaps

| Item | Severity | Plan |
|---|---|---|
| Consent timestamp for WhatsApp/email consent stored as a single timestamptz column rather than full audit trail | Medium | Add `consent_whatsapp_at`, `consent_whatsapp_revoked_at` columns |
| Hard delete is admin-only | Medium | Add in-app "delete this customer" with cascading object cleanup |
| No data-export-on-request flow | Low | Add CSV-of-my-data download in CustomerDetailView |
| Children data (Section 9) | Not applicable | The boutique does not serve minors |
| Cross-border to Google for VTO | Documented, mitigated by Google's no-retention policy | Add explicit consent line in the VTO consent script |
