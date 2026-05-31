# Runbook — Bad Deploy Rollback

**When to use:** A TestFlight build, App Store release, Supabase migration, or Edge Function deploy is causing user-visible problems. You need to revert in under 30 minutes.

---

## Symptoms that should trigger this runbook

| Signal | Likely cause |
|---|---|
| App crashes on launch on testers' iPads | Bad build pushed to TestFlight |
| Save / record actions fail across the board | Bad Supabase migration; bad RLS policy |
| Owner reports "I can't log in" | Auth flow regression or expired refresh-token bug |
| Photos don't load anywhere | Storage RLS or signed-URL persistence regression |
| Gemini calls return 4xx for everything | API key revoked or URL/header change broke calls |

---

## Decision: full rollback or hotfix?

Ask: can you ship a fix faster than rolling back?
- **Build issue** (Swift error): always rollback — even if the fix is one line, the build+sign+upload cycle is 20-30 min
- **Migration / RLS issue**: rollback always preferred — write a forward-migration revert
- **Edge Function**: rollback by redeploying previous version (1 min)
- **Secret rotation**: hotfix only path (no rollback)

---

## Procedure

### iPad app build

1. **Expire the bad TestFlight build**
   - App Store Connect → TestFlight → Builds → tap the bad build → "Expire build"
   - Existing testers see "this build is no longer available" on next launch
2. **Confirm previous build is still available**
   - Same TestFlight builds list — should see the prior version "Active"
3. **Communicate**
   - WhatsApp the boutique owner: "I've expired build X. Please reopen the app; you'll be on the previous good version. Working on the fix."
4. **Hot-fix workflow**
   - Branch off the previous build's tag
   - Cherry-pick the broken commit OUT
   - `cd ipad && xcodegen generate && xcodebuild archive ...`
   - Upload, submit, expire interim build if needed

### Supabase schema migration

Migrations are forward-only by convention. Rollback = a new migration that reverts.

1. **Identify the bad migration**
   ```bash
   # Locally
   ls supabase/migrations | tail -5
   ```
2. **Write a revert migration**
   ```bash
   # If bad migration was 0027_add_thing.sql, write:
   cat > supabase/migrations/0028_revert_thing.sql <<'EOF'
   -- Revert 0027 — broke X behavior because Y
   alter table public.things drop column if exists thing_column;
   -- ... revert each statement in reverse order
   EOF
   ```
3. **Apply via Supabase MCP**
   ```
   mcp__supabase__apply_migration(project_id: tdnwdlrkbrtoxjzcgusg, name: "revert_thing", query: ...)
   ```
4. **Verify** — run the smoke test from `README.md`
5. **Document** — add an entry to CHANGELOG.md noting what went wrong

### Edge Function rollback

1. **List versions**
   - Supabase Dashboard → Edge Functions → `purge-expired-tryons` (or relevant) → Versions tab
2. **Re-deploy previous version source**
   - From git: `git show <prev-commit>:supabase/functions/<name>/index.ts > /tmp/index.ts`
   - Re-deploy via MCP:
     ```
     mcp__supabase__deploy_edge_function(
       project_id: tdnwdlrkbrtoxjzcgusg,
       name: "<name>",
       files: [{name: "index.ts", content: <contents>}]
     )
     ```
3. **Verify** — invoke the function endpoint, check logs in dashboard

### Disable an Edge Function entirely

If the function is causing more harm than not running:
- Supabase Dashboard → Edge Functions → toggle "Active" off
- Document why in CHANGELOG.md

---

## Communication template

```
Hi [boutique owner], we found an issue with the latest update and we've
rolled back to the previous version. The fix is in progress and we'll
ship a corrected build by [time]. Nothing was lost — all your data is
safe. Please continue using the app as normal.
```

---

## Postmortem checklist

After service is restored, before next deploy:
- [ ] Add a unit/regression test that would have caught this
- [ ] Document the failure mode in CHANGELOG.md under "Known issues fixed"
- [ ] If schema-related, add a CHECK constraint to prevent the same shape of error
- [ ] If Edge Function-related, add input validation to prevent the trigger condition
- [ ] If deploy process was at fault (e.g. forgot to test), update `docs/deployment.md`
