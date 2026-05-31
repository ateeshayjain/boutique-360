# ADR 0003 — Google Gemini for AI sketch→render and virtual try-on

**Date:** 2026-05-25 (during Plan 4-5: magic moment)
**Status:** Accepted

---

## Context

The magic moment is **sketch → AI render → virtual try-on**. This needs:
1. **Image-to-image generation** — take a pencil sketch + style hints, return a photorealistic garment
2. **Image composition** — take a render of a garment + a photo of a customer, return the customer wearing the garment
3. **Text generation** — Hinglish tailor brief for the karigar (separate flow)

Constraints:
- **India market** — prices in USD must convert to reasonable INR margins
- **Customer trust** — biometric data (customer's face for VTO) crosses borders to whichever vendor we pick. The vendor's data-retention policy matters legally.
- **DPDP Act compliance** — vendor must not retain inputs beyond the response
- **Latency** — sketch→render must complete in ~30s; customer can wait but not 2 minutes
- **Cost** — ~₹400 / boutique / day budget is the cost-ceiling target

Vendors evaluated:
1. **Google Gemini** (`gemini-2.5-flash-image`, `gemini-2.5-flash`)
2. **OpenAI** (`gpt-image-1`, GPT-4o + DALL-E)
3. **Anthropic Claude** (text only; no image generation)
4. **Replicate** (hosted Stable Diffusion / FLUX / etc.)

---

## Decision

Use **Google Gemini 2.5** for all AI features:
- `gemini-2.5-flash-image` for sketch→render + virtual try-on (image generation)
- `gemini-2.5-flash` for tailor brief (text generation, ~40x cheaper than image gen)

Integration:
- Direct REST calls from `Services/GeminiService.swift`
- Auth via `x-goog-api-key` header
- Per-boutique daily cost ceiling enforced server-side via `record_ai_usage` Postgres function

---

## Consequences

### What becomes easier
- **Cheap** — `gemini-2.5-flash-image` is ~$0.04 per call vs ~$0.17 for DALL-E 3. At the $5/day ceiling, that's ~125 renders/day per boutique — well above realistic usage.
- **Fast** — Flash variants are tuned for sub-30s image generation
- **Reasonable image quality** for the use case — boutique sketch fidelity, not Hollywood VFX
- **Data retention is API-only** — Google states the Gemini API does not retain image data after the response. (Per their published API terms, October 2025.)
- **One vendor for text + image** — simpler ops, single API key, single quota dashboard
- **Multimodal in one call** — `contents` array can hold the sketch + fabric reference images + text prompt, returned as image + text in a single response

### What becomes harder
- **Lock-in to Google API** — if Gemini quality degrades or pricing changes, switching costs ~1 day to swap in a different vendor's REST shape
- **Image quality is "good enough", not "best"** — Midjourney v6 or FLUX 1.1 Pro produce more photorealistic garments. Boutique customers might prefer those eventually.
- **No fine-tuning** — Gemini doesn't yet expose image-model fine-tuning. If we wanted to teach the model the boutique's specific design vocabulary, we can't.
- **DPDP audit nuance** — customer photo goes to Google's servers (not Mumbai). We've documented this in `docs/privacy-policy.md` + the consent capture script must mention it.

### What becomes impossible
- **Truly local AI** (privacy-maximalist) — no on-device option. Apple's `VisionKit` doesn't do image generation. Mitigated by 7-day purge policy.

---

## Alternatives considered

### OpenAI (gpt-image-1 / DALL-E 3)
- Pro: arguably best image quality; mature SDK
- Con: ~4x the per-call cost; API has had stricter rate limiting for image gen; data residency unclear for the photo
- **Why rejected:** the cost ceiling matters for a boutique business — at $0.17/render, a busy festive day blows past the cap

### Anthropic Claude
- Pro: best text generation in our internal testing; would beat Gemini Flash for Hinglish brief
- Con: **no image generation at all**. Would need a second vendor for sketch→render, doubling the integration surface.
- **Why rejected:** "one vendor for text + image" weighed more than the marginal quality win on text. If image-gen were not table-stakes, Claude would win for text.

### Replicate (hosted FLUX 1.1 Pro / Stable Diffusion XL)
- Pro: model choice — pick the best image model per task; reasonable pricing
- Con: API surface is per-model, not unified; cold-start latency varies; data-retention policies vary per model owner
- **Why rejected:** the vendor-pluggability we could use here isn't paying for the operational complexity right now

### Local Stable Diffusion on a Mac mini in the boutique
- Pro: zero cross-border data, zero per-call cost
- Con: requires a Mac, requires CoreML optimization, would be 2-3x slower than Gemini Flash on an iPad
- **Why rejected:** "the boutique buys a Mac" is a non-starter. Out of scope.

---

## Risks accepted

| Risk | Mitigation |
|---|---|
| Gemini pricing increase | Server-side cost ceiling caps exposure at $5/boutique/day |
| Google deprecates Gemini 2.5 Flash | Migration to next Gemini generation is API-compatible; runbook in `docs/runbooks/gemini-outage.md` covers transient outages |
| Image quality complaints | Could swap in FLUX or DALL-E for the render step (keeping Gemini for text) — ~half-day integration if needed |
| Customer photo retained by Google despite policy | We have only Google's documented promise. Mitigation: don't repeat the same customer photo to the API; rely on the 7-day local purge as our defensible boundary. |

---

## Related

- ADR 0002 — Supabase backend (consent record lives there; Edge Function purges photos)
- `Services/GeminiService.swift` — implementation
- `Services/AICostMeter.swift` + `record_ai_usage` RPC — cost ceiling enforcement
- `docs/dpdp-compliance.md` — cross-border processing posture
- `docs/runbooks/gemini-outage.md` — what to do when Gemini is down
- `docs/privacy-policy.md` — customer-facing disclosure
