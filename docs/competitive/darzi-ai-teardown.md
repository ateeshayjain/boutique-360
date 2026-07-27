# Competitive Teardown — Darzi AI ("Boutique OS")

**Date:** July 2026 · **Sources:** darziai.in marketing site + web search.
**Confidence caveat:** this is a *marketing-site* teardown — no hands-on trial,
no pricing page (404), no app-store listing found. Claims below are what they
*advertise*, which may over- or under-state what ships. A 7-day trial run is
the obvious next step to harden this.

## 1. Snapshot

| Dimension | Darzi AI | Boutique 360 |
|---|---|---|
| Positioning | "Heritage CRM & AI Virtual Try-On" for Indian tailors + boutiques | iPad-native CRM + AI design studio for a designer boutique |
| Platform | **Web dashboard + phone/laptop**; mobile app unspecified | **iPad-only native SwiftUI** |
| Target | Small tailors → large designer studios (broad) | Single designer boutique (deep, pilot) |
| Languages | Hindi + English UI; Hinglish marketing copy | English UI; **Hinglish karigar job cards** |
| Business model | SaaS + **AI credits** (try-on metered); 7-day trial, no card; referral program (credits for referrals) | Owner-operated tool; Gemini cost-ceiling per boutique |
| Pricing | **Not public** — demo-led sales (`/contact`), `/pricing` 404s | n/a (not sold yet) |
| Sales motion | Free demo booking, WhatsApp contact line, Instagram presence | n/a |

## 2. Feature-by-feature

| Capability | Darzi AI (advertised) | Boutique 360 (shipped) | Edge |
|---|---|---|---|
| Customer profiles + notes | ✅ | ✅ + tags, VIP, spend panel, timeline | ≈ / B360 deeper |
| Measurements saved/reused | ✅ | ✅ + history per garment type | ≈ |
| Order flow | ✅ Pending → Trial → Ready | ✅ 7-state machine + inquiries funnel | ≈ / B360 deeper |
| Payments/ledger | ✅ advances, balance auto-update, customer ledger | ✅ advances/balance + Razorpay links | ≈ |
| GST invoice | ✅ generate + WhatsApp share | ✅ CGST/SGST PDF + monthly GST CSV export | ≈ / B360 compliance deeper |
| **Automated WhatsApp reminders** | ✅ **automated** trial/payment/ready messages | ⚠️ owner-reviewed `wa.me` links (deliberate, ADR 0005) | **Darzi** (automation) |
| **Staff access control** | ✅ PIN-based; finance separated from orders | ❌ single-owner (deferred) | **Darzi** |
| AI try-on | ✅ "show customer the final dress before tailoring" + skin-tone color suggestions | ✅ Gemini VTO from *your own rendered design* | different — see §3 |
| AI extras | Fabric quantity estimates, style recs by occasion/body type, "Fiza" assistant | Style suggestions from purchase history, Hinglish tailor briefs | ≈ different bets |
| **Design creation** | ❌ none — no sketching, no rendering from scratch | ✅ Pencil canvas, garment templates, fabric overlays, reference-photo studio, photoreal render | **B360 — the moat** |
| Job cards for karigars | ❌ not mentioned | ✅ hybrid PDF + AI Hinglish brief | **B360** |
| Fabric estimates | ✅ AI quantity estimate | ❌ (inventory on roadmap) | **Darzi** (lightweight) |
| Fabric *inventory* | ❌ not mentioned | ❌ roadmap | open ground for both |
| Data privacy | Privacy policy page only; no DPDP claims | DPDP consent-at-capture + 7-day photo auto-purge | **B360** |
| Offline/at-the-table UX | Web forms | Native iPad consultation-table UX | **B360** |

## 3. The key product difference — where the try-on comes from

Both have "AI try-on," but they are different products underneath:

- **Darzi AI:** try-on appears to work from *existing garment/fabric imagery* —
  show the customer roughly how the finished piece will look. It is a
  **sales-reassurance feature** bolted onto a CRM. No design pipeline feeds it.
- **Boutique 360:** try-on is the *last step of a design pipeline* — reference
  photo or Pencil sketch → fabric overlays → photoreal render → try-on of
  **that specific design**. The VTO shows a garment that doesn't exist yet
  because the studio just designed it.

Implication: Darzi's try-on is copyable by anyone with a FASHN-style API key
(and will be copied — Darzee's "Fiza", Juvee's voice ERP are already adding AI
veneers). The design-pipeline-to-try-on thread is much harder to retrofit onto
a form-based web CRM.

## 4. What Darzi AI does better (real threats)

1. **Automated WhatsApp reminders** — trial date, payment due, order ready,
   fired automatically. B360 keeps a human in the loop by design; for busy
   shops automation wins. *Response: our CustomerNotifier + status hooks are
   one flag away from "auto-draft, one-tap-approve-all" — do that, keep the
   review step as a differentiator rather than a tax.*
2. **PIN-based staff roles** — finance hidden from tailors. They shipped the
   thing we deferred. *Confirms multi-role staff should move up the backlog.*
3. **Fabric quantity estimates** — cheap AI feature, high daily utility.
   *Trivially addable to our job-card composer (Gemini already writes the
   brief; ask it for meters too).*
4. **Go-to-market machinery** — trial, credits, referral loop, demo funnel,
   Instagram. B360 has none (not selling yet), but if it ever does, this is
   the playbook to study.
5. **Web = zero-install, any device.** Their tailor on a ₹8k Android phone can
   use it; B360 needs an iPad. Segment split, but it caps their ceiling on
   design quality and caps our floor on reach.

## 5. What Boutique 360 owns (the moat, confirmed)

1. **The studio** — no sketching, rendering, or design creation anywhere in
   Darzi AI. The Pencil + template + fabric + render pipeline is uncontested.
2. **The Look thread** — reference → design → VTO → lock → job card → invoice
   as one object's lifecycle. Darzi manages *records*; B360 manages *the
   garment's life*.
3. **Karigar-facing output** — Hinglish job cards. Their languages are for the
   *owner's UI*; ours is for the *production floor*.
4. **Compliance depth** — DPDP consent + auto-purge, CGST/SGST + GST CSV.
5. **iPad consultation UX** — the selling moment happens across a table, not
   at a desk after the customer leaves.

## 6. Strategic implications

- **Category timing:** "CRM + AI try-on" is now a *category* in India (Darzi
  AI, Darzee+Fiza, Juvee, RunTailor). Assume 12–18 months before basic AI
  try-on is table stakes in every ₹500/mo tailoring app.
- **Don't fight on CRM features** — that layer is commoditized and Darzi/Darzee
  will always be cheaper and broader. Fight on the design studio + Look
  lifecycle, which requires a different device, different UX, and a pipeline
  they'd have to rebuild from scratch.
- **Steal three things:** (a) auto-drafted reminders with one-tap approve,
  (b) PIN-scoped staff roles, (c) fabric-meters estimate in the job card.
- **Watch items:** Darzi AI shipping any sketch/design tool; pricing going
  public (signals scale); an iPad app; a fabric-inventory module.

## 7. Open questions (need a trial account to answer)

- What does one AI credit cost and what does one try-on consume?
- Try-on input: customer photo? stock model? own catalog?
- Is the "mobile app" native or a web wrapper?
- Order volume limits per plan; multi-boutique support?
- Actual quality of the try-on renders vs Gemini 2.5-flash-image.
