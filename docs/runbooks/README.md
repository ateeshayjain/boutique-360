# Runbooks

Operational playbooks for common failure modes. Each runbook follows the same structure:

1. **When to use** — clear trigger conditions
2. **Symptoms** — what the owner / monitoring will see
3. **Triage** — quick (≤5 min) diagnostic steps
4. **Resolution paths** — branched fixes for likely root causes
5. **Communication template** — what to message the boutique owner
6. **Postmortem checklist** — what to add after service is restored to prevent recurrence

---

## Runbook index

| Runbook | Severity | Last reviewed |
|---|---|---|
| [bad-deploy-rollback.md](bad-deploy-rollback.md) | P0 | 2026-05-28 |
| [gemini-outage.md](gemini-outage.md) | P1 (AI features only; other flows work) | 2026-05-28 |
| [multi-tenant-onboarding.md](multi-tenant-onboarding.md) | n/a (operational, not incident) | 2026-05-28 |

---

## Planned runbooks (not yet written)

| Runbook | Why needed |
|---|---|
| `supabase-outage.md` | Full app blocked when Supabase region is down — what to communicate, how to verify region failover |
| `rls-misconfiguration.md` | Wrong RLS policy → cross-tenant data leak. Detection + rollback steps. |
| `dpdp-photo-purge-failure.md` | If `purge-expired-tryons` Edge Function fails 2 days in a row, what's the manual purge procedure |
| `apple-developer-account-issues.md` | Provisioning expired, certificates revoked, app removed from TestFlight |
| `whatsapp-handoff-breaking.md` | If `wa.me` URLs stop opening WhatsApp (rare — would be Apple changing URL routing behavior) |

These will be added as we encounter the failure modes or as pre-emptive planning before launch.

---

## How to add a new runbook

Use the existing 2 as templates. Aim for:
- **Read time ≤ 2 minutes** — owner can scan during a real incident
- **Specific Supabase/Apple/Google URLs and CLI commands**, not abstract guidance
- **Communication template** in the runbook so the responder doesn't draft from scratch under stress
- **Postmortem checklist** that prevents recurrence
