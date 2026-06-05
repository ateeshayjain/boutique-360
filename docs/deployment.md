# Deployment — Boutique 360

## Environments

| Env | Supabase project | iPad target | Status |
|---|---|---|---|
| **Production** | `tdnwdlrkbrtoxjzcgusg` (ap-south-1) | TestFlight + future App Store | Live |
| **Staging** | not yet provisioned | TestFlight beta | Planned |
| **Development** | same as production with seed `demo@boutique360.test` | Local simulator + `-auto-demo` arg | Live |

For pilot stage, production and development share the same Supabase project. When customer count exceeds 1 boutique, a separate staging environment will be provisioned.

---

## First-time machine setup

```bash
# Prereqs
brew install xcodegen supabase

# Clone
git clone <repo>
cd boutique-360

# iPad app
cd ipad
cp Boutique360/Configuration/Secrets.xcconfig.example Boutique360/Configuration/Secrets.xcconfig
# Edit Secrets.xcconfig and set GEMINI_API_KEY = AIzaSy...
xcodegen generate
open Boutique360.xcodeproj
```

Run on simulator: `Cmd+R`. Add launch arg `-auto-demo` (Edit Scheme → Arguments) to sign in as the demo account automatically.

---

## Schema changes (Supabase)

Schema lives in `supabase/migrations/`. Numbered SQL files apply forward-only.

```bash
# Authoring a new migration
N=$(printf "%04d" $(($(ls supabase/migrations | tail -1 | cut -c1-4) + 1)))
echo "-- $(date +%F): description" > supabase/migrations/${N}_description.sql
# write SQL
```

Apply via Supabase MCP (in this conversation):
```
mcp__supabase__apply_migration(
  project_id: tdnwdlrkbrtoxjzcgusg,
  name: descriptive_name,
  query: <SQL contents>
)
```

Or via CLI:
```bash
supabase link --project-ref tdnwdlrkbrtoxjzcgusg
supabase db push
```

**Rule**: every Swift model change is paired with a migration in the same PR. Models that drift from schema cause silent decode failures.

---

## Edge Functions

Deployed via Supabase MCP `deploy_edge_function` or:
```bash
supabase functions deploy purge-expired-tryons
```

Cron-invoked functions are registered in a migration:
```sql
select cron.schedule(
  'job-name',
  '30 21 * * *',
  $$ select net.http_post(url := '…', headers := '…') $$
);
```

Current functions:
| Name | Trigger | Purpose |
|---|---|---|
| `purge-expired-tryons` | pg_cron daily @ 21:00 UTC (02:30 IST) | DPDP customer-photo purge |

---

## iPad app — distribution

### TestFlight (current)

```bash
cd ipad
xcodegen generate
xcodebuild -project Boutique360.xcodeproj \
    -scheme Boutique360 \
    -archivePath build/Boutique360.xcarchive \
    archive

xcodebuild -exportArchive \
    -archivePath build/Boutique360.xcarchive \
    -exportPath build/export \
    -exportOptionsPlist build/ExportOptions.plist

xcrun altool --upload-app \
    -f build/export/Boutique360.ipa \
    -t ios \
    -u <apple-id> \
    -p <app-specific-password>
```

A signing identity + provisioning profile (`com.boutique360.designer.ipad`) must already be configured in Xcode for the team.

### App Store (future)

Same archive, manual review in App Store Connect. First submission needs:
- Privacy nutrition label (declare: name, phone, photos)
- App Store screenshots (12.9" iPad Pro required, plus 11")
- Privacy policy URL
- Demo account credentials for review (the `demo@boutique360.test` works)

---

## Secret rotation

| Secret | Where | Rotation |
|---|---|---|
| Supabase service role key | Supabase dashboard → Settings → API | When suspected leak; updates Edge Functions automatically |
| Supabase anon key | Same | Rare — public-safe (RLS protects data) |
| Gemini API key | Google AI Studio | Every 90 days (planned); store in Secrets.xcconfig |
| Apple signing identity | Xcode preferences | Per developer; not a project secret |

---

## Monitoring (current and planned)

| Layer | Tool | Status |
|---|---|---|
| Supabase queries | Supabase Logs (dashboard) | Live, manual check |
| Edge Function errors | Supabase Logs | Live, manual check |
| iPad crashes | Xcode Organizer (TestFlight) | Live for beta users |
| Gemini API errors | Caught and surfaced via ErrorBus | Live |
| Cron failures | None (pg_cron.job_run_details) | Planned: weekly report |
| Customer-photo purge | Function returns row count; no alerting | Planned: alert when purge fails 2 days in a row |

---

## Rollback procedure

### Schema rollback
Migrations are forward-only. Rollback = write a new migration that reverts. Test in development first.

### App rollback
TestFlight: tap "Expire" on the bad build → users on it get a prompt to update. New build with the fix shipped same day.

App Store: phased release defaults to 1% on day 1, scaled over 7 days. Emergency rollback = "Pause release" in App Store Connect, then submit a fix-build.

### Edge Function rollback
Re-deploy the previous version: pull from git history, redeploy. Or disable in dashboard.

---

## Known operational quirks

- **Xcodegen warning**: project.yml lists Configuration files in two places (configFiles + sources/excludes). Cosmetic; build succeeds.
- **Gemini latency**: text generation ~3s, image generation ~30s. UI shows ProgressView + estimated time.
- **Indian network conditions**: VTO uploads can fail at the customer's end. Owner retries.
- **Supabase Free tier**: pilot uses Free. Will need Pro ($25/mo) when storage exceeds 1GB or Edge Function invocations exceed 500k/mo.
