# Runbook — Onboarding a new boutique (multi-tenant)

**When to use:** A new boutique has signed up. They need their own row in the database, their own staff account, their own (defaulted) settings — but they share the same Supabase project, codebase, and Edge Functions as boutique #1.

**Estimated time:** 15-30 minutes per boutique. Most of it is collecting boutique-specific info (name, GSTIN, address, default GST rate, business hours).

---

## Before you start

Have these from the new boutique:
- Legal business name
- GSTIN (optional but required before they can issue invoices)
- Place of supply (state — drives CGST/SGST vs IGST split)
- Address (used on invoices)
- Owner's email (for magic-link sign-in)
- Owner's preferred default GST rate (5% for most apparel; 12% / 18% for HSN-specific items)

---

## Procedure

### Step 1 — Create the boutique row

```sql
-- Run via mcp__supabase__execute_sql
-- A short slug helps with future URL routing
insert into public.boutiques (name, slug, gstin, place_of_supply, address, default_gst_rate)
values (
  'Anokhi Designs',
  'anokhi',
  '07AABCS1234A1Z5',           -- nullable; can be added later via Settings
  'Delhi',
  '14, Khan Market, New Delhi 110003',
  5.0
)
returning id;
```

Note the returned `id` — you'll use it in steps 3-5.

### Step 2 — Verify default loyalty tiers exist for the boutique

Loyalty tiers are global reference data per Plan 1 — they don't need per-boutique copies. If you've changed this since: re-check the seed.

```sql
select count(*) from public.loyalty_tiers;
-- Should return >= 3 (Silver / Gold / Platinum)
```

### Step 3 — Create the owner's Supabase Auth user

In Supabase Dashboard → Authentication → Users → "Add user" → "Send invitation":
- Email: `<owner-email>`
- Auto-confirm: yes (skips the email-verification round-trip)

Note the returned user ID.

**OR** via SQL if you have the service role key:
```sql
-- This is the SQL path; safer to use the dashboard
-- which handles the email-change column GoTrue expects
```

### Step 4 — Link the owner to the boutique via staff_users

This is the row that RLS uses to scope all queries. **Without this row, the user cannot read anything.**

```sql
-- Wait until the user has signed in once via the magic link
-- so the auth.users row is fully provisioned, then:

insert into public.staff_users (user_id, boutique_id, name, role)
values (
  '<auth-user-id-from-step-3>',
  '<boutique-id-from-step-1>',
  'Owner Name',
  'owner'
);
```

**Alternative**: the `trg_staff_user_bootstrap` trigger (migration 0020) creates a default `staff_users` row pointing to the **first boutique** when a new auth user signs in. This was correct for the single-boutique pilot but **MUST be disabled or scoped before onboarding boutique #2** — otherwise every new user lands on boutique #1.

To disable the trigger before onboarding:
```sql
drop trigger if exists trg_staff_user_bootstrap on auth.users;
```

This makes step 4 (manual `staff_users` insert) mandatory, which is correct for multi-tenant.

### Step 5 — Seed boutique-specific settings (optional)

```sql
-- Workshop stages (custom karigar flow)
insert into public.settings (boutique_id, key, value_json)
values ('<boutique-id>', 'workshop_stages',
        '["Cutting", "Stitching", "Embroidery", "Trial fitting", "Finishing", "QC", "Ready"]');
```

If the boutique uses different stage names ("Hand Embroidery" vs "Aari Work"), customize the JSON array. The job-card flow will respect these.

### Step 6 — Verify RLS isolation

Sign in as the new owner and confirm:

```bash
# Should return ONLY their own boutique
curl "${SUPABASE_URL}/rest/v1/boutiques?select=*" \
  -H "apikey: ${SUPABASE_ANON_KEY}" \
  -H "Authorization: Bearer ${NEW_OWNER_JWT}"
```

Sign in as boutique #1 and confirm they **don't see boutique #2**:

```bash
curl "${SUPABASE_URL}/rest/v1/customers?select=*" \
  -H "apikey: ${SUPABASE_ANON_KEY}" \
  -H "Authorization: Bearer ${OLD_OWNER_JWT}"
# Should return ONLY boutique #1's customers
```

If either query leaks across boutiques: STOP. RLS is broken. Investigate before proceeding.

### Step 7 — TestFlight invite

Add the owner's Apple ID email to the TestFlight tester list. Send them install instructions.

### Step 8 — First-run validation

Watch the owner sign in for the first time. Verify:
- ✅ Magic link arrives
- ✅ Universal Link opens Boutique 360
- ✅ Dashboard shows boutique name correctly (proves Step 4 worked)
- ✅ "No orders yet" empty state (proves Step 6 isolation)
- ✅ Settings → Boutique shows the name, GSTIN, address from Step 1

### Step 9 — Document the boutique

Add an entry to `docs/onboarded-boutiques.md` (create if it doesn't exist):

```markdown
| Boutique | Onboarded | Owner | Supabase user_id | Notes |
|---|---|---|---|---|
| Aditi Designer Studio | 2026-05-25 | Aditi (founding pilot) | ... | First boutique; default loyalty tiers + workshop stages |
| Anokhi Designs | 2026-XX-XX | Owner Name | ... | Place of supply: Delhi; default GST 5% |
```

This makes onboarding tracking explicit.

---

## What can go wrong

| Symptom | Cause | Fix |
|---|---|---|
| New owner sees "no boutique context" on sign-in | Step 4 not done (no `staff_users` row) OR trigger from old single-tenant pattern landed them on boutique #1 | Manually insert `staff_users` row pointing to the correct boutique |
| New owner sees boutique #1's data | RLS policy missing or wrong on a table | Check `pg_policies` for the affected table; should filter by `boutique_id = current_boutique_id()` |
| GST CSV export shows ₹0 | `default_gst_rate` is nil + no orders yet | Expected for day 1; will populate after first sale |
| Invoices show old boutique name | `BoutiqueContext` cached the previous boutique; sign out + back in | Reproducible only if a previous user signed in on this device |
| AI cost ceiling already exceeded on day 1 | `ai_usage_daily` table shared across boutiques but unique on `(boutique_id, usage_date)` — should be fine | Check `select * from ai_usage_daily where boutique_id = '<new>'` — should be 0 rows |

---

## When you've onboarded the 5th boutique

The single-tenant assumptions from Plan 1 start breaking. Re-evaluate:

1. **`trg_staff_user_bootstrap`** — must be disabled if not already
2. **WhatsApp Business API** (see ADR 0005) — automation becomes worth the cost
3. **Per-boutique branding** — `boutique.brand_color_hex` should drive accent color in the app + invoice PDFs
4. **Staging environment** — separate Supabase project for testing migrations before applying to production
5. **Pricing tier model** — is each boutique on Pro tier? Or do we move them to a shared Enterprise plan?
6. **Per-tenant feature flags** — some may pay for AI features, some not
7. **Owner-self-onboarding flow** — manual SQL doesn't scale; build a CLI tool or web admin

This runbook will need to evolve into an onboarding admin interface around that point.

---

## Related

- ADR 0002 — Supabase choice (RLS as the multi-tenant boundary)
- `docs/architecture.md` — Core design rule #7 (RLS belt-and-braces)
- `supabase/migrations/0020_rls_subquery_fix_and_staff_bootstrap.sql` — the trigger that needs disabling
- `supabase/migrations/0017_rls_helpers.sql` — `current_boutique_id()` function
