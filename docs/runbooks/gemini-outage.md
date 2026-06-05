# Runbook — Gemini Outage

**When to use:** AI features in the app (sketch→render, virtual try-on, tailor brief generation) are failing for all users. Owner sees error toasts or stuck spinners on Gemini-backed flows.

---

## Symptoms

| Signal | Likely cause |
|---|---|
| Render button completes but image is blank | API returned 200 but body had no image — model-level issue |
| "Couldn't reach server" / generic network error on Gemini | Google API outage OR our network failure |
| "Daily AI cost ceiling reached" toast across multiple boutiques | Counter mis-configured (e.g. cap accidentally set to $0.01) |
| 401 / 403 errors in logs | API key rotated / revoked / quota exhausted |
| Steady 5xx from `generativelanguage.googleapis.com` | Google-side incident |

---

## Triage (3 minutes)

1. **Check Google AI status page**
   - https://status.cloud.google.com/ (filter by Vertex AI / Generative Language)
2. **Check our Supabase Logs for recent Gemini errors**
   - Supabase Dashboard → Edge Functions / Logs → filter `generativelanguage.googleapis.com`
3. **Test with curl** (replace key from Vault):
   ```bash
   curl -X POST \
     -H "x-goog-api-key: $GEMINI_KEY" \
     -H "Content-Type: application/json" \
     -d '{"contents":[{"role":"user","parts":[{"text":"hello"}]}]}' \
     "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
   ```
   - 200 → key/network OK, problem is downstream (cost ceiling? specific model?)
   - 401/403 → key issue (rotate)
   - 5xx → Google-side; wait

---

## Resolution paths

### Path A — Google-side outage
1. **Confirm via status page**
2. **Communicate to boutique**: WhatsApp:
   > "Our AI is temporarily unavailable because Google's service is down. Non-AI features (orders, payments, invoices, customers) all still work. We'll let you know when it's back."
3. **Do nothing in our code** — Gemini calls will throw, the `ErrorBus` toast informs the owner, non-AI flows continue.
4. **Monitor** — refresh status page every 15 min. When green, AI flows resume automatically.

### Path B — API key revoked / quota exhausted
1. **Check Google AI Studio** → API key usage
2. **If quota exhausted**: bump quota or wait for daily reset (00:00 PT)
3. **If key revoked**: rotate
   - Generate new key in Google AI Studio
   - Update `ipad/Boutique360/Configuration/Secrets.xcconfig`
   - Rebuild + ship via TestFlight Hotfix
   - **Key rotation requires a build** because we hardcode at build-time in Secrets.xcconfig. Future improvement: fetch the key from Supabase Vault at runtime.

### Path C — Daily AI cost ceiling tripped
The Postgres function `record_ai_usage` raises when `cost_estimate_usd > p_daily_cap_usd` (default $5/boutique/day).

1. **Check the counter**
   ```sql
   select * from public.ai_usage_daily
    where boutique_id = '<id>'
      and usage_date = current_date;
   ```
2. **If legitimately high usage** (boutique had a busy day): raise the cap one-time
   ```sql
   -- Call the RPC with a higher p_daily_cap_usd parameter from the iPad
   -- OR insert a per-boutique override row in a future settings table.
   ```
3. **If a stuck retry loop** (counter shows 1000+ calls in an hour): investigate the client. Add a per-minute throttle to GeminiService.

### Path D — Model returned blank/invalid image
1. **Reproduce locally** — try the same sketch with the curl command
2. **If consistent**: switch model in `GeminiService.swift`:
   ```swift
   private static let model = "gemini-2.5-flash-image-preview"  // fallback
   ```
3. **If transient**: add retry-once logic to `generateImage()` with a 2-second delay before retry

---

## Mitigation we already have

- **ErrorBus toast** surfaces failures clearly so owner isn't confused
- **AI-disabled fallback** in JobCardComposer when Gemini key missing — owner can still ship the job card with manually-typed brief
- **Cost ceiling** caps Google bills at $5/boutique/day even in worst case (stuck retry loop)
- **DPDP**: even if Gemini outage stops VTO results, the consent timestamp is captured before the call, so audit trail remains intact

---

## Communication template

```
Hi [owner], our AI features are temporarily down due to a Google service
issue. You can still:
✓ Create customers, orders, payments, invoices
✓ Use sketch canvas (just without the AI render)
✓ Send WhatsApp messages
✓ Generate GST reports

AI render + virtual try-on will be back shortly. I'll update you when fixed.
```

---

## Postmortem checklist

- [ ] If outage lasted >1 hour, add a "fallback mode" toggle in Settings so owner can deliberately skip AI features without seeing error toasts on every attempt
- [ ] Document the outage duration + root cause in CHANGELOG.md
- [ ] If Google-side: subscribe to Google AI status RSS for proactive alerts
