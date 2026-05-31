# Architecture Decision Records (ADRs)

ADRs capture the *why* behind significant architecture choices. They prevent future contributors from re-litigating decisions without context.

## Format

Each ADR follows [Michael Nygard's classic structure](https://www.cognitect.com/blog/2011/11/15/documenting-architecture-decisions):

- **Status** — Proposed / Accepted / Superseded / Deprecated
- **Context** — what's the situation that forces a decision
- **Decision** — what we chose
- **Consequences** — what becomes easier, harder, or impossible as a result

## Numbering

ADRs are numbered sequentially. **Numbers are never reused** — even if an ADR is superseded, its number stays valid. A new ADR may say "Supersedes ADR 0003" and reference it forever.

## Index

| # | Status | Title |
|---|---|---|
| [0001](0001-native-ipad-over-flutter.md) | Accepted | Native iPad app with SwiftUI over Flutter / React Native |
| [0002](0002-supabase-over-rolled-backend.md) | Accepted | Supabase as the only backend instead of rolling our own |
| [0003](0003-gemini-over-openai-or-claude.md) | Accepted | Google Gemini for AI sketch→render and virtual try-on |
| [0004](0004-magic-link-over-password-auth.md) | Accepted | Magic-link sign-in instead of password authentication |
| [0005](0005-wa-me-over-whatsapp-business-api.md) | Accepted | `wa.me` deep links instead of WhatsApp Business API |

## When to add a new ADR

Write an ADR when the decision will be re-asked in 6 months by someone who wasn't in the room. Specifically:

- **Choosing a third-party service or SDK** (auth provider, payment processor, AI vendor)
- **Choosing an architectural pattern** (offline-first vs online-only, monolith vs microservices)
- **Choosing a cross-cutting policy** (error-handling model, persistence strategy, multi-tenancy boundary)
- **Saying no to something obvious** (e.g., "we're not adopting Combine even though it would simplify reactivity")

Don't write ADRs for:
- Variable naming
- File organization (use `docs/architecture.md` instead)
- Single-line bug fixes
- Library version bumps
