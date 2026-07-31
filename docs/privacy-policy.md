# Privacy Policy — Boutique 360

**Effective date:** [TO BE FILLED IN BEFORE APP STORE SUBMISSION]
**Operator:** [Boutique business name + GSTIN]
**Contact:** [owner@boutique.example] · [+91-XXXXXXXXXX]

This document explains what personal data Boutique 360 collects, why, how long we keep it, who can see it, and your rights as a customer of the boutique using this app.

This policy is grounded in the **Digital Personal Data Protection Act 2023** ("DPDP Act") of India. Internal technical detail and audit posture: see `docs/dpdp-compliance.md`.

---

## In one sentence

The boutique uses this app to remember your name, contact, measurements, and design preferences so they can serve you better. If you let them use AI to virtually try a design on your photo, that photo is automatically deleted within 7 days unless you ask them to save it.

---

## What we collect

| Data | Why | Stored where |
|---|---|---|
| **Your name, phone, email, address** | Identify you when you walk in or message. Send order updates. | Supabase database (Mumbai region) |
| **Your date of birth and important dates** (anniversaries, festivals you celebrate) | Greet you on the right day, suggest seasonally appropriate outfits | Same |
| **Your measurements** (bust, waist, hip, etc. as relevant per garment) | Make clothes that fit you | Same |
| **Your style preferences** (favorite colors, fabrics you love or avoid, body type, budget band) | Recommend designs you'll like | Same |
| **Notes from your visits** (occasion, conversation context) | Pick up where we left off next time you visit | Same |
| **A photo of you, used once for a virtual try-on** (if you consent at the time) | Show you how a design would look on you, before we make it | Supabase Storage (Mumbai region), **auto-deleted within 7 days** unless you ask us to save it to your style lookbook |
| **Records of your orders, payments, and invoices** | Run our business. Required by Indian Income Tax + GST law. | Same |
| **A record of reminders we've sent you** (which reminder, which day) | Avoid messaging you twice about the same fitting or balance | Same |
| **Progress photos of your garment**, taken by the tailor | Track work in progress. These are photos of the clothing, not of you | Same |

We **do not** collect:
- Your bank account or card details (we use UPI / card terminals separately, not in this app)
- Your location
- Your contacts list, photos, microphone, or anything else from your phone

---

## Your virtual try-on photo — special treatment

The photo of yourself you provide for a virtual try-on is treated as sensitive personal data:

1. The boutique owner explicitly asks for your consent verbally, then records that consent (with the timestamp and your name) in the app before any processing.
2. Your photo is sent **once** to Google's Gemini AI service to composite the garment onto you. Google's API terms state they do not retain image data after the response.
3. The composited result is shown to you and may be shared with you via WhatsApp.
4. **Both your original photo and the result are automatically deleted within 7 days** (a daily background process runs at 03:00 IST). The exception is if you explicitly ask the boutique to save the look to your style lookbook for future reference.
5. You can ask the boutique to delete your photo immediately at any time, no questions asked.

The processing legal basis under DPDP Section 6 is your explicit consent. You can revoke it at any time.

---

## Who can see your data

- **The boutique owner** (single named operator) who uses the iPad app
- **A boutique assistant**, if the owner hands them the iPad. Assistants see
  your name, contact, measurements and order status, but payments, invoices
  and pricing are hidden from them until an owner unlocks the app
- **The karigar (tailor) making your outfit**, who receives a private web link
  for your job card. That page shows **your first name only, plus the
  measurements needed to make the garment** — never your phone number, email,
  or address. The link is unguessable, can be revoked by the boutique, and the
  karigar may upload progress photos *of the garment* through it
- **Supabase, our hosting provider**, who stores the data encrypted on servers physically located in Mumbai (ap-south-1)
- **Google's Gemini AI service**, *only* for the specific moment a virtual try-on or AI design render runs — see above
- **The boutique's chartered accountant**, when monthly GST reports include your order / invoice information (statutory tax filing)
- **No one else.** We do not sell, share, or advertise based on your data.

---

## How long we keep your data

| Data class | Retention | Reason |
|---|---|---|
| Virtual try-on photo (yours + the result) | 7 days, or until you ask us to save it | Limit biometric data exposure |
| Name, contact, measurements, preferences | While the commercial relationship is ongoing, or until you ask us to delete | Continuing service |
| Order, payment, invoice records | 8 years | Indian Income Tax Act + GST Act requirements (overrides general retention) |
| Reminder history, garment progress photos | While the commercial relationship is ongoing, or until you ask us to delete | Continuing service. **These are not on an automatic timer** — unlike try-on photos, they are deleted on request rather than on a schedule |

---

## Your rights (under DPDP Sections 11-13)

You have the right to:

| Right | How to use it |
|---|---|
| **Know what data we have** about you | Ask the boutique to show you your record on the iPad |
| **Correct anything inaccurate** | Same — owner can update on the spot |
| **Have your data erased** | Ask the boutique. We will delete everything except records required by tax law. |
| **Withdraw consent** for WhatsApp / virtual try-on / email | Ask the boutique to toggle the consent off |
| **Raise a grievance** | Contact the boutique directly (WhatsApp / in person). For unresolved issues, you may approach the Data Protection Board of India. |

We aim to act on these requests **within 7 days**.

---

## Security

- All data is encrypted in transit (TLS 1.3)
- All data is encrypted at rest (Supabase platform default)
- Access requires authentication; only the boutique owner's named account can read or modify the data
- Customer data is isolated per boutique via row-level security policies
- Sessions are bound to device passcode via iOS Keychain
- The Gemini API key is stored as a header, not logged in URLs

The technical detail of our security posture is in `docs/dpdp-compliance.md`.

---

## Children

Boutique 360 is operated for adult bridal / formal-wear clients. We do not knowingly process data of children under 18. If you are a parent / guardian and believe your child's data was collected, please contact the boutique to have it deleted.

---

## Changes to this policy

We may update this policy. If we make material changes, the boutique will inform you via the channel you already use to communicate with them (typically WhatsApp). The effective date at the top of this page will be updated.

---

## Contact

[Boutique business name]
[Address]
GSTIN: [if applicable]
Phone / WhatsApp: [+91-XXXXXXXXXX]
Email: [owner@boutique.example]

Grievance Officer: [Name]
Same contact details apply.

---

*Last reviewed: [DATE]*
*Next review: 6 months from above*
