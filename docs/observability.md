# Observability — Boutique 360

How we know what's happening inside the app + backend, and what's planned vs shipped.

---

## Pillars

The classic observability pillars are **logs / metrics / traces**. Our current state and target by surface:

| Layer | Logs | Metrics | Traces |
|---|---|---|---|
| iPad app | ✅ `os.Logger` adopted (this pass) | ❌ no in-app metrics | ❌ no client-side tracing |
| Supabase Postgres | ✅ platform-managed query logs | ✅ dashboard (query volume, slow queries) | ❌ not exposed |
| Supabase Edge Function | ✅ platform-managed function logs | ⚠️ invocation count via dashboard | ❌ not exposed |
| Gemini API | N/A | ⚠️ daily-cost counter via `ai_usage_daily` | ❌ not exposed |
| TestFlight crashes | ✅ Xcode Organizer | ✅ crash-free session % | N/A |

**Today the design is sound at "ship to one boutique" scale.** Gaps become P1 when boutique count > 5.

---

## iPad-side logging (shipped 2026-05-28)

### Foundation

`Utilities/Log.swift` defines a `Log` namespace with subsystem `com.boutique360.designer.ipad` and category-scoped loggers:

```swift
Log.auth          // sign-in, magic-link, sign-out
Log.network       // Supabase + Gemini HTTP calls
Log.storage       // upload, download, signed URL
Log.ai            // Gemini call lifecycle + cost meter
Log.notifications // schedule + permission + fire
Log.business      // status changes, payments, orders
Log.app           // catch-all
```

### Privacy specifiers

iOS unified logging supports per-value privacy:

```swift
Log.auth.notice("magic-link sent to \(email, privacy: .private)")
Log.business.notice("order \(orderNumber, privacy: .public) → \(status.rawValue, privacy: .public)")
Log.network.error("Gemini auth failed: \(apiKey, privacy: .sensitive)")
```

- `.public` — value included in logs
- `.private` — visible in DEBUG, redacted in Release (DPDP-safe)
- `.sensitive` — always redacted, even in DEBUG
- (default for non-numeric) — `.private`

### Levels

| Level | When to use | Example |
|---|---|---|
| `.debug` | Verbose diagnostics; not retained long | "AI call accepted, cost $0.04" |
| `.info` | Normal operation milestones | "daily-briefing scheduled" |
| `.notice` | Significant events (worth noticing in logs) | order status transitions, sign-in/out |
| `.error` | Recoverable failures | "magic-link request failed: <reason>" |
| `.fault` | Bug indicators | "force-unwrap reached unreachable branch" |

### Viewing logs

**During development (Xcode):**
- Debug area shows all `Log.*` output by default

**On a real device:**
```bash
# All Boutique 360 logs from the last hour
log show --last 1h --predicate 'subsystem == "com.boutique360.designer.ipad"'

# Just business events (orders, payments)
log show --last 1h --predicate 'subsystem == "com.boutique360.designer.ipad" AND category == "business"'

# Errors only
log show --last 1h --predicate 'subsystem == "com.boutique360.designer.ipad" AND messageType == "error"'
```

**Console.app** on a Mac can mirror logs from a connected iPad in real time. Filter by subsystem.

### What we log today

Strategic points (kept lean — over-logging is its own anti-pattern):

| Call site | Category | Level | What |
|---|---|---|---|
| `AuthService.signInWithMagicLink` | auth | info / notice / error | Request submitted, sent, or failed |
| `AuthService.signOut` | auth | notice / error | Sign-out lifecycle |
| `AICostMeter.checkCeiling` | ai | debug / error | Call accepted (debug) or ceiling hit (error) |
| `OrdersService.updateStatus` | business | notice | Status transition with order number |
| `NotificationsService.scheduleDailyBriefing` | notifications | info / error | Schedule outcome |

This is the **minimum viable set** for "what happened?" questions. Expand as specific debugging needs arise. Don't pre-emptively log every method entry — the noise hurts diagnostic quality.

### What we deliberately don't log

- **Customer names, phones, emails, photos** — never in app-side logs (DPDP)
- **Payment amounts** — could be considered sensitive financial data; the audit trail is the DB, not logs
- **API keys, JWTs, refresh tokens** — even `.sensitive`-tagged, we just don't log them at all
- **Sketch / render image bytes** — too large; just log "render started/done"

---

## Backend logging (Supabase)

Supabase Cloud captures:
- All PostgREST requests (path, status code, latency, JWT user)
- All Edge Function invocations (timing, status, log output from `console.log`)
- All `pg_cron` job runs (`cron.job_run_details` view)
- Auth events (sign-ins, password resets, token refreshes)

Visible in Supabase Dashboard → Logs. No setup required.

Search examples:
- Find every cross-boutique RLS violation: filter by status 401 + path contains `/rest/v1`
- Find DPDP purge failures: filter by edge function `purge-expired-tryons` + status 5xx
- Find slow queries: dashboard's "Performance" tab surfaces queries > 100ms

---

## Metrics

### What we measure today

| Metric | Source | Where it lives |
|---|---|---|
| Daily Gemini cost per boutique | `ai_usage_daily` table | Postgres, queried via dashboard |
| Order status distribution | Aggregated client-side on Dashboard load | View only, not stored |
| Today's revenue | Aggregated client-side via `PaymentsService.capturedSinceMidnight` | View only |
| TestFlight crash-free sessions | Apple-collected | Xcode Organizer |

### What we don't measure (deferred)

| Metric | Why deferred | Plan |
|---|---|---|
| API call latency p50/p95/p99 | Single-tenant; ad-hoc Supabase dashboard sufficient | Adopt PostHog or Mixpanel for client-side timing |
| User flow completion rates | Pilot scale; user is the developer | Same as above |
| Gemini call success rate / latency | Failures surfaced via ErrorBus immediately | Track in `ai_usage_daily` if pattern emerges |
| TestFlight install funnel | Single user | Apple Analytics when public |

---

## Alerting

### Today

| Trigger | Channel |
|---|---|
| TestFlight build crashes | Email from Apple |
| Supabase project status (downtime) | Email from Supabase |
| Manual dashboard checks | Owner reports → fix |

**No automated alerts on app errors yet.** This is the biggest gap.

### Planned

| Trigger | Channel | When to add |
|---|---|---|
| `purge-expired-tryons` fails 2 days in a row | Slack webhook | Before multi-tenant SaaS — DPDP risk |
| Daily AI cost > 80% of cap for any boutique | Slack webhook | Same time; gives heads-up before hard cap hits |
| Supabase 5xx burst (>10/min) | Slack via log drain | Same time |
| RLS denial spike (cross-tenant access attempts) | Slack via log drain | Required before public/SaaS |
| Pilot owner reports app crash | Manual (WhatsApp) | Already true |

---

## Tracing

Not implemented. Single iPad app + Supabase backend doesn't need distributed tracing for the pilot scale. When we have:
- Web admin → backend → multiple Edge Functions → DB
- Customer-facing public website
- Background workers

...then OpenTelemetry adoption becomes worth it.

---

## Correlation IDs

Not yet implemented. The placeholder:
- Each iPad request to Supabase could carry a `x-request-id` header with a UUID
- Edge Functions could log the same ID
- Postgres logs would include it too

This makes "trace one user's flow across system layers" possible. Adding this is ~1-2 hours of work and worth doing the day after we have a second engineer who needs to debug something they didn't write.

---

## Performance baselines

As of 2026-05-28:

| Operation | Target | Observed |
|---|---|---|
| App launch → Dashboard rendered | <2s | ~1.2s on M5 iPad simulator, cold |
| Dashboard `load()` (5 parallel fetches) | <500ms | ~300ms warm-cached, ~800ms cold |
| Sketch → AI render (Gemini Flash Image) | <30s | 18-25s typical, 40s+ outliers |
| Virtual try-on | <30s | similar |
| Tailor brief generation | <5s | 2-4s typical |
| Invoice PDF generation | <500ms | ~200ms (PDFKit is fast) |
| GST CSV export (50 orders) | <2s | ~500ms |
| Sign-in via magic link | depends on email | <10s typical |

If observed values drift above target, we file a perf issue and investigate before merging more features.

---

## Postmortem template (when something breaks)

After service is restored, before next deploy:

```markdown
## Incident <YYYY-MM-DD-N>: <short title>

**Duration:** <start time> – <end time> (<minutes>)
**Severity:** Sev1 / Sev2 / Sev3
**Affected:** <boutiques> · <surfaces>

### What happened
<one paragraph plain English>

### Root cause
<technical, specific. Reference commit hash if relevant.>

### Detection
- How was the failure noticed?
- Could it have been detected sooner? By what?

### Resolution
- Specific steps that fixed it
- Was the runbook used? Did it work?

### Action items
- [ ] Add test that catches this class of bug
- [ ] Update runbook if procedure was unclear
- [ ] Add alert/log so similar future failures are detected automatically
- [ ] Documentation update (CHANGELOG, ADR if architectural)

### Timeline
- HH:MM — first symptom
- HH:MM — owner reports / alert fires
- HH:MM — diagnosis
- HH:MM — fix applied
- HH:MM — service restored
- HH:MM — confirmed stable
```

This template is in `docs/runbooks/` adjacent to the specific runbooks. Use it consistently — over time the pattern of "this kind of bug always comes from this kind of cause" becomes visible.

---

## Related

- `Utilities/Log.swift` — log foundation
- `Services/AICostMeter.swift` + `ai_usage_daily` table — cost telemetry
- `docs/runbooks/` — operational responses to observed problems
- ADR 0002 — Supabase choice (their logs are part of why we picked them)
