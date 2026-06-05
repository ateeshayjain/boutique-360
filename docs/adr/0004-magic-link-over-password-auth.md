# ADR 0004 — Magic-link sign-in instead of password authentication

**Date:** 2026-05-25 (Plan 2: iPad foundation)
**Status:** Accepted

---

## Context

The boutique owner needs to sign in on their iPad. Options:
1. **Email + password** with Supabase Auth
2. **Magic link** (passwordless) — email a one-time link, tap to sign in
3. **Phone OTP** (SMS) — phone number + OTP via SMS gateway
4. **Apple Sign-In** — iOS-native, no password
5. **Google Sign-In / Microsoft Entra** — federated identity

Constraints:
- **Single user per device** — the owner uses one iPad, signs in once, stays signed in for months
- **Low cognitive load** — owner is non-technical, doesn't want password managers
- **No app-internal payment flows** — so we don't need step-up auth or biometric re-auth on sensitive actions
- **WhatsApp is the customer-facing channel** — phone OTP would conflate "I'm authenticating Boutique 360" with WhatsApp's own OTP flow, confusing

---

## Decision

Use **magic-link sign-in** via Supabase Auth.

Flow:
1. Owner enters email
2. Supabase sends a magic link to that email
3. Owner taps link in their mail app
4. iOS Universal Link routes back to Boutique 360
5. `Boutique360App.onOpenURL` → `AuthService.handleAuthCallback(url:)` → session established
6. Session token persists in Keychain — owner doesn't sign in again for months unless they explicitly sign out

Additional decisions:
- **Universal links** (apex domain: `app.boutique360.com`) for the redirect
- **Demo password sign-in is `#if DEBUG`-gated** so the dev escape hatch (`demo@boutique360.test`) doesn't ship to Release builds
- **No biometric re-auth** on sensitive actions (yet) — the device passcode + Keychain binding is the security model

---

## Consequences

### What becomes easier
- **Zero password management** — no "I forgot my password" flow, no password strength enforcement code path, no breach-risk surface
- **Cognitive simplicity** — owner doesn't memorize anything; email is already in their life
- **Phishing-resistant by design** — there's no password for a phishing site to steal. (The link itself is a single-use token; reuse fails.)
- **Native iOS integration** — Universal Links handle the round-trip; no browser pop-up
- **Single sign-in per device** — Keychain persistence means months between auth events

### What becomes harder
- **Email-dependency** — if the owner can't access their email on this device, they can't sign in. Mitigation: the link works on any device that opens it, so checking email on their phone and tapping the link still triggers the iPad sign-in if Universal Links are set up correctly (they're not yet — currently the link opens the app on whichever device taps it).
- **Slow first-time signup** — owner waits for email delivery (typically <10s, but feels long)
- **No "remember this device" UI** — Supabase handles this internally with refresh tokens; the UX is "you're just always signed in" which is correct but doesn't give owner a sense of control

### What becomes impossible (without adding more)
- **Multi-user with role separation** in this app — only one staff_users row per Supabase user. If we add a second person at the boutique (the helper/assistant), we'd need a second account.

---

## Alternatives considered

### Email + password
- Pro: universally understood
- Con: requires password manager OR weak passwords OR forgot-flow UI. Owner is non-technical, so passwords add friction without security upside.
- **Why rejected:** the security cost-benefit of passwords for a single-user-per-device boutique app is negative. Magic link wins.

### Phone OTP (SMS)
- Pro: India-friendly, no email dependency
- Con: SMS gateway fees (~₹0.20-0.50/message in India); OTP fatigue; conflates with WhatsApp's customer-facing flow
- **Why rejected:** SMS infrastructure is a recurring cost for a feature that fires once every few months

### Apple Sign-In
- Pro: native, fast, no app-server contract
- Con: requires the owner to have an Apple ID set up with email (~80% do, but the 20% who don't would be blocked); Apple's SDK has been historically buggy with Universal Links + Sign-In together
- **Why rejected:** Add as a "Sign in with Apple" button alongside magic link in a future iteration — not the primary path

### Google / Microsoft federated
- Pro: zero new credentials
- Con: implies multi-vendor authorization complexity; the boutique owner may not have a Google account they want associated with their business
- **Why rejected:** introducing federation when one vendor (Supabase) handles auth natively is over-engineering

---

## Risks accepted

| Risk | Mitigation |
|---|---|
| Owner's email gets compromised | Same blast radius as for any service they sign into with email. Out of scope to defend against. |
| Magic link intercepted in email transit | TLS to mail providers + Supabase signs the link with a server-side secret. Token expires after 1 hour. |
| Phishing email impersonating Boutique 360 | The magic link points to our exact domain; iOS Universal Link verification rejects mismatched domains. |
| Owner switches devices mid-flow | Today: works; we don't bind sessions to device identifiers. Future: when adding more security, may add device-binding. |

---

## Related

- ADR 0002 — Supabase backend (Auth is part of the platform)
- `Features/Auth/SignInView.swift` — email input + magic-link request
- `Services/AuthService.swift` — session management
- `Boutique360App.swift` — `onOpenURL` callback handling
- `Configuration/Boutique360.entitlements` — Universal Links domain declaration
