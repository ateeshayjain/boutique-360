# Release Checklist — Boutique 360

**Context that shapes this list:** one boutique, one iPad, used daily in
production. There is no staging environment and no second tenant to catch a
bad migration. The database is shared between "dev" and "prod" because they
are the same database. That single fact is why the ordering below is
deliberately migration-first and reversibility-obsessed.

Work top to bottom. Anything marked **STOP** is a release blocker, not a
nice-to-have.

---

## 1. Before you start

- [ ] Working tree clean; on `main`; `git log` matches what you intend to ship.
- [ ] Read `SECURITY_REVIEW.md` §9 (declared gaps). Confirm nothing there has
      become a blocker since it was written.
- [ ] Confirm no one is mid-transaction on the iPad (the owner is using this
      device for real customers — coordinate a quiet window).

---

## 2. Version

- [ ] Bump `CFBundleShortVersionString` in `ipad/Boutique360/Info.plist`
      (currently `0.1.0`).
- [ ] Bump `CFBundleVersion` — must be **strictly greater** than the last
      build uploaded to App Store Connect, or the upload is rejected after
      the whole archive has already been built.
- [ ] Update `CHANGELOG.md`.

---

## 3. Secrets and build configuration — **STOP items**

- [ ] **Demo sign-in is `#if DEBUG`-gated and therefore absent from Release.**
      Verify by building for Release and confirming the "Continue as demo"
      button does not appear.
      Evidence: `Features/Auth/SignInView.swift:95,120`.
      *This is the single most dangerous item on the list — a Release build
      shipping a hardcoded demo login is a full account compromise.*
- [ ] `Secrets.xcconfig` exists locally, is **not** tracked
      (`git ls-files | grep Secrets.xcconfig` must return only the
      `.example`), and holds production keys.
- [ ] `Env.xcconfig` points at the production Supabase project
      (`tdnwdlrkbrtoxjzcgusg`), not a branch database.
- [ ] Gemini key is a production key with a billing ceiling configured
      server-side. Confirm `AICostMeter` default ($5/boutique/day) is
      appropriate.
- [ ] Optional integrations (SendGrid / Twilio / Razorpay): either configured
      with production credentials, or deliberately left disabled. Both are
      valid; a half-configured integration is not.

---

## 4. Database migrations — do this **before** shipping the app

The app and schema are deployed independently, and the app is the thing users
get last. Migrations must be forward-compatible with the *currently installed*
build, because an owner who doesn't update still runs against the new schema.

- [ ] Every new migration is additive, or safe against the previous app build.
- [ ] Apply via the Supabase MCP; record the applied name.
- [ ] **Verify RLS as an authenticated user, never as `service_role`.**
      `service_role` bypasses RLS entirely — this is exactly how the R3 lock
      feature shipped non-functional (`SECURITY_REVIEW.md` §6).
- [ ] Probe new policies with an **INSERT**, not a SELECT. A SELECT with no
      matching policy returns HTTP 200 and `[]`, indistinguishable from "no
      rows exist."
- [ ] Confirm the migration file is committed to `supabase/migrations/`.
      **Nine applied migrations are currently missing from the repo**
      (`SECURITY_REVIEW.md` §9) — do not make it ten.

---

## 5. Build and test

- [ ] `cd ipad && xcodegen generate` (mandatory after any file add/remove).
- [ ] Full suite green: `xcodebuild test …` — **220 tests** as of 2026-07-31.
- [ ] Release build compiles without warnings introduced by this change.
- [ ] Manual smoke on a real iPad (not just the simulator): sign in, open an
      order, generate an invoice, send one WhatsApp message.

---

## 6. Feature-specific gates

Add a section here whenever a feature has a verification that unit tests
cannot reach. Current entries:

- [ ] **R4b role gate** — the nine manual QA steps in
      `docs/superpowers/plans/2026-07-28-reminders-roles.md` (Task B5 Step 4).
      Steps 2, 4 and 7 are the ones that matter: force-quit stays assistant,
      force-quit keeps the cooldown, winding the device clock stays capped.
      **Status as of 2026-07-31: NOT RUN** (blocked on Xcode simulator
      selection). Unit tests cover the persistence primitives and the
      clock-independence logic, but no one has observed the behaviour on a
      device. **This is a STOP item for any release that includes R4b.**
- [ ] **DPDP purge** — confirm `cron.job_run_details` shows recent successes:
      ```sql
      select status, count(*), max(end_time) from cron.job_run_details
      where jobid = 1 group by status;
      ```

---

## 7. Ship

- [ ] Archive, upload to App Store Connect, distribute via TestFlight to the
      owner's device first.
- [ ] Owner confirms the build works on their real data before wider release.
- [ ] Tag the release: `git tag v<version> && git push --tags`.
- [ ] Push to `origin main:boutique-360-ipad-app`.
      **Never force-push remote `main`** — it holds an unrelated pre-app stub.

---

## 8. Rollback

Know the answer before you need it.

| What broke | Rollback |
|---|---|
| **App build** | Re-distribute the previous TestFlight build. The owner's iPad can reinstall it immediately. This is fast and safe. |
| **Migration** | **There is no automatic rollback.** Forward-only migrations, one shared database, live data. Recovery means writing a compensating migration by hand, or restoring from a Supabase point-in-time backup and losing everything since. |
| **Edge Function** | Redeploy the previous version from git. |
| **A bad RLS policy** | Symptom is usually 403s or empty lists in the app, *not* an error. Check `SECURITY_REVIEW.md` §6 for the diagnosis pattern. |

**The asymmetry is the point:** app rollback is cheap, migration rollback is
close to impossible. That is why §4 comes before §5, and why a migration
should be reviewed harder than the Swift code that uses it.

See also `docs/runbooks/` for bad-deploy and Gemini-outage playbooks.

---

## 9. After release

- [ ] Watch `events` for errors in the first day of real use.
- [ ] Confirm the AI cost ceiling has not been hit unexpectedly.
- [ ] Update `docs/app-map.md` and `README.md` if the feature set changed.
