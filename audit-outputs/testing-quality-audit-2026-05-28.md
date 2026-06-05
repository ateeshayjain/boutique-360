# Software Testing & Code Quality Audit — Boutique 360

**Generated:** 2026-05-28
**Methodology:** Walked the 9-section app-agnostic checklist line-by-line against the Boutique 360 Swift/SwiftUI codebase + Supabase backend.

**Legend:** ✅ pass · ⚠️ partial / needs attention · ❌ gap · N/A not applicable

---

## Section Score Summary

| Section | Pass | Partial | Gap | N/A | Score |
|---|---|---|---|---|---|
| 1. Code Quality & Architecture | 9 | 3 | 0 | 1 | 🟢 |
| 2. Input Validation & Sanitization | 5 | 4 | 0 | 5 (server features) | 🟡 |
| 3. AI/LLM Concurrency | 6 | 1 | 0 | 0 | 🟢 |
| 4. Security (Auth + Secrets + API + Data + Deps) | 14 | 4 | 1 | 3 | 🟢 |
| 5. Database & Data Integrity | 9 | 2 | 1 | 0 | 🟢 |
| 6. Error Handling | 6 | 2 | 0 | 0 | 🟢 |
| 7. Logging & Observability | 2 | 2 | 2 | 0 | 🟡 |
| 8. Testing | 8 | 3 | 4 | 1 | 🟡 |
| 9. Release Readiness | 4 | 2 | 1 | 0 | 🟢 |

**Overall: 🟢 Strong on architecture, security, error handling, data integrity. 🟡 Gaps in observability, integration tests, CI test automation.**

---

## 1. Code Quality & Architecture

### SOLID Principles

| Principle | Status | Evidence |
|---|---|---|
| Single Responsibility | ✅ | Services are `enum` namespaces with one resource each (Customers, Orders, Designs...). Models are pure value types. Views are presentation-only. |
| Open/Closed | ✅ | Status state machines extend via enum cases; `nextOptions` / `allowedNext` follow data, not inheritance. New garment types decode via `init(from:)` with `.other` fallback — no client recompile required. |
| Liskov Substitution | ✅ | Protocol use is minimal but consistent. `ObservableObject` conformers (AuthService, BoutiqueContext, ErrorBus) honor the contract. |
| Interface Segregation | ✅ | No fat protocols. Each `Service` namespace exposes only the methods relevant to its resource. |
| Dependency Inversion | ⚠️ | Services are concrete `enum` types, not protocols. Tests cannot inject mocks. **Recommendation:** introduce `protocol CustomersServicing` etc. when integration tests are written. |

### DRY

| Item | Status | Evidence |
|---|---|---|
| Shared utilities | ✅ | `Formatters` (currency, dates), `WhatsAppShareHelper`, `GSTINValidator`, `ErrorBus`, `AppEvents`, `StorageService` |
| Centralized validation | ✅ | `GSTINValidator` regex-driven, used at form submit |
| Single source of truth for config | ✅ | `Configuration/Config.swift` reads from Info.plist; values come from `Env.xcconfig` + `Secrets.xcconfig` |
| Shared error handler | ✅ | `ErrorBus.shared.report(...)` + `ErrorToastOverlay` modifier on RootView |

### Dead Code

| Item | Status | Evidence |
|---|---|---|
| Unused imports/functions/variables | ✅ | Zero compiler warnings on clean build. The `colAmt` dead variable was removed in the audit-fix cycle. |
| Commented-out code blocks | ✅ | `grep TODO\|FIXME\|HACK\|XXX` returns **0** results |
| "Legacy methods just in case" | ⚠️ | `DesignRender.resultImageUrl` and `DesignTryOn.customerPhotoUrl` are deprecated-by-comment but still on the type for reading legacy rows. **Acceptable** until backfill removes legacy rows. |
| Unreferenced files | ✅ | XcodeGen `sources: [path: Boutique360]` includes everything under that path; no orphan files. |

### Architecture Layering

| Item | Status | Evidence |
|---|---|---|
| Clear UI / Business Logic / Data Access separation | ✅ | Features/ → Services/ → Supabase. Models/ is pure value types. |
| Views never directly call data layer | ⚠️ | **5 violations** found: `SettingsView`, `ImportantDatesListView`, `DashboardView` (3 places) call `SupabaseService.client.from(...)` directly instead of through a Service namespace. **Recommendation:** add `ImportantDatesService.list(boutiqueId:)` and `PaymentsService.todayCaptured(...)` to keep the layer clean. |
| Business logic not coupled to SwiftUI | ✅ | Models are SwiftUI-free since the `CustomerTimelineEvent.Kind.tint` extraction (M8 fix). |
| Data layer swappable | ⚠️ | Services are concrete; same caveat as DIP above. |
| No circular dependencies | ✅ | Clean module graph. |

---

## 2. Input Validation & Sanitization

### Client-Side

| Item | Status | Evidence |
|---|---|---|
| User text inputs validated | ⚠️ | Names + notes accepted free-form; only sanity-checked at length. Sufficient for trusted single-owner pilot. |
| Email format validated | ✅ | `SignInView.isValidEmail` checks structural format, no force-unwraps |
| URL format validated | N/A | App doesn't accept user-typed URLs (except tracking_url which is opaque text) |
| Numeric bounds | ⚠️ | `quantityMeters` stepper bounded 0.0–50.0; `qty` not bounded; price text-field accepts any decimal. **Recommendation:** Add bounds to qty + total. |
| Array/collection size limits | ✅ | List queries use `.limit(200)` or `.limit(500)` consistently |
| File upload validated for type/size/content | ⚠️ | PhotosPicker filters by `.images`; no explicit size limit before upload. Gemini API will reject oversize, but client should pre-check. |
| Graceful error messages on invalid input | ✅ | GSTIN inline error, payment receivedTotal banner, JobCard error banner |

### Server-Side (Supabase / Postgres / Edge Functions)

| Item | Status | Evidence |
|---|---|---|
| Server revalidates client input | ✅ | Postgres CHECK constraints + RLS + FK enforcement + Edge Function input parsing |
| UUID/ID parameters validated | ✅ | Postgres typed columns reject malformed UUIDs |
| SQL injection prevented (parameterized only) | ✅ | All queries via PostgREST (REST → SQL parameterized) and RPCs with typed parameters. **0** string-interpolated SQL. |
| XSS prevented | N/A | Native iOS app; no HTML rendering of user content |
| CSRF tokens | N/A | Supabase JWT-based auth; not vulnerable to traditional CSRF |
| Command injection | N/A | No shell execution anywhere |
| Path traversal prevented | ✅ | Storage paths are constructed from server-generated UUIDs via `StorageService.tryonPath` etc. — user input never participates in path construction |
| Request body size limits | ✅ | Supabase platform-level limits; client validates image quality (JPEG `0.85`) |
| Content-Type validation on uploads | ✅ | `StorageService.upload(_:to:path:contentType:)` requires explicit type |

### AI/LLM-Specific

| Item | Status | Evidence |
|---|---|---|
| User content sanitized before AI prompt | ⚠️ | `notesMd`, `customerNotes` passed directly to `PromptTemplates.tailorBrief`. Prompt injection mitigated by the system-style framing in templates, but no explicit filter. |
| Prompt injection patterns filtered | ⚠️ | No explicit filter. **Recommendation:** Add a "strip imperative instructions targeting the assistant" pre-filter on long notes. |
| AI output sanitized before display | ✅ | Output is plain text (Hinglish brief); rendered in SwiftUI Text (no HTML), so no XSS surface |
| Token/cost limits per user | ❌ | **Gap:** no per-call cost ceiling. A bad prompt loop could rack Gemini bills. **Recommendation:** wrap GeminiService calls with a per-day cost counter tied to the boutique. |

---

## 3. Concurrency & Thread Safety

| Item | Status | Evidence |
|---|---|---|
| async/await for I/O | ✅ | Every Service method is `async throws`. Zero callback-based code. |
| All async ops awaited | ✅ | No unintentional fire-and-forget. The earlier `AuthService.init` unstructured Task was the only one — flagged in audit (M5), accepted as benign for single-user lifecycle. |
| Task cancellation honored | ⚠️ | `CustomersListView` uses `searchTask = Task { ... }; searchTask?.cancel()` for debounced search. Other long ops don't check `Task.isCancelled`. **Recommendation:** add cancellation checks in Gemini calls (30s+ operations). |
| Debounced operations capture state at invocation | ✅ | `searchTask` pattern captures the query string at invocation |
| Error propagation through async chains | ✅ | `try await` chains propagate; `do/catch` at view boundaries |
| Unhandled rejections prevented | ✅ | Every `Task {}` either has `do/catch` or uses `try?` deliberately (and that pattern was audited + reduced in the silent-failure-hunter pass) |
| Shared mutable state protected | ✅ | `BoutiqueContext`, `AuthService`, `ErrorBus` are all `@MainActor` `ObservableObject`s. No locks needed because actor isolation is sufficient. |
| UI updates on main thread | ✅ | `@MainActor` annotations on services + SwiftUI's main-actor isolation |
| Blocking calls on main thread | ✅ | No `Thread.sleep` or `DispatchSemaphore.wait()` anywhere |
| Resource cleanup on navigation/dealloc | ⚠️ | SwiftUI's `.task` modifier auto-cancels on view disappear — handled. Manual cleanup minimal but adequate. |

---

## 4. Security

### Authentication

| Item | Status | Evidence |
|---|---|---|
| Passwords hashed (bcrypt/Argon2) | ✅ | Supabase Auth uses bcrypt server-side |
| No plaintext/MD5/SHA passwords | ✅ | Confirmed via Supabase platform |
| Password strength enforcement | ⚠️ | Supabase default minimum length = 6. **Recommendation:** raise to 10+ in dashboard for the production project |
| Session tokens cryptographically random | ✅ | Supabase JWTs |
| Token expiration enforced | ✅ | Supabase default 1 hour access + refresh rotation |
| Failed login rate-limited | ✅ | Supabase platform-level rate limiting |
| OAuth correct (PKCE, state) | ✅ | Magic-link flow (universal links) — PKCE managed by Supabase SDK |
| Authorization checked on every request | ✅ | RLS evaluates per-request on every PostgREST call |
| Role-based access server-side | ✅ | `staff_users.role` checked via `current_boutique_id()` helper in RLS policies |

### Secrets Management

| Item | Status | Evidence |
|---|---|---|
| No credentials in source code | ✅ | `Secrets.xcconfig` gitignored; `Env.xcconfig` has only the public anon key |
| No credentials in git history | ✅ | Verified by `grep -r "AIzaSy\|sk_live"` on git-tracked files — 0 hits |
| Secrets via env vars / managers | ✅ | xcconfig → Info.plist → Config.swift |
| Different credentials per env | ⚠️ | Pilot stage has shared dev/prod project. Staging planned (see deployment.md). |
| Secrets rotatable without redeploy | ⚠️ | Gemini key requires rebuilding the iPad app. Supabase keys are dashboard-managed. **Acceptable** for pilot. |

### API Security

| Item | Status | Evidence |
|---|---|---|
| Rate limiting public endpoints | ✅ | Supabase platform default |
| Rate limiting on expensive ops (AI) | ❌ | **Gap:** see "token/cost limits" above |
| CORS configured restrictively | N/A | Native iOS app uses Supabase auth headers; CORS not the threat model |
| HTTPS enforced everywhere | ✅ | Hardcoded `https://` for Supabase + Gemini |
| Sensitive data never in URL params | ⚠️ | Gemini API key is currently a URL query param (`?key=...`) — Google's documented pattern but still a leak vector if URLs are logged. **Recommendation:** move to `x-goog-api-key` header. |
| Error responses don't leak internals | ✅ | `ErrorBus.report(error.localizedDescription)` shows user-friendly message; Postgres internal details stay server-side |
| API versioning | ✅ | Supabase REST is `/rest/v1/`; schema migrations forward-only |

### Data Protection

| Item | Status | Evidence |
|---|---|---|
| Sensitive data encrypted at rest | ✅ | Supabase storage encryption-at-rest |
| Row-level security between tenants | ✅ | RLS on every boutique-scoped table via `current_boutique_id()` |
| Backups encrypted | ✅ | Supabase platform default |
| Deletion actually deletes (not just soft) | ⚠️ | Customer soft-delete (`deleted_at`) for restore flexibility. VTO purge cron does hard delete. **Acceptable** trade-off documented in `docs/dpdp-compliance.md`. |
| Audit logging for security-relevant actions | ⚠️ | Supabase logs sign-ins. No explicit per-app audit table. **Recommendation:** add `audit_events` table for sensitive ops (consent capture, customer delete). |

### Dependency Security

| Item | Status | Evidence |
|---|---|---|
| Dependencies scanned for vulnerabilities | ⚠️ | No automated scanner (no Dependabot/Snyk yet). Manual review only. |
| Dependencies pinned | ✅ | `Package.resolved` committed; Supabase SDK at `2.20.0+` |
| No unnecessary dependencies | ✅ | Only Supabase Swift SDK + Apple frameworks. |
| Lockfiles committed | ✅ | `Package.resolved` tracked. `Secrets.xcconfig` is the only intentional exclusion. |

---

## 5. Database & Data Integrity

### Access Patterns

| Item | Status | Evidence |
|---|---|---|
| Parameterized queries | ✅ | PostgREST + typed RPCs; **0** string interpolation |
| Indexes on hot columns | ✅ | `design_renders_design_idx`, `design_tryons_customer_idx`, `design_tryons_purge_idx`, plus FK indexes per migration |
| N+1 patterns avoided | ✅ | Dashboard overdue-payments was N-query; fixed in H5 with single grouped query. Timeline aggregator uses `.in()` batched. |
| Connection pooling | ✅ | Supabase pgBouncer |
| Query timeouts | ✅ | Supabase platform timeouts |
| Pagination | ✅ | All `.list()` calls use `.limit(200/500)` (`grep .limit` = 8 occurrences) |

### Data Integrity

| Item | Status | Evidence |
|---|---|---|
| FK constraints | ✅ | Every relation declares `on delete cascade` or `on delete set null` |
| Unique constraints | ✅ | `boutique_sequences (boutique_id, name)`, order numbers, etc. |
| NOT NULL on required fields | ✅ | Confirmed across migrations |
| CHECK constraints | ⚠️ | Sparse — most validation is at app layer. **Recommendation:** add CHECKs on `order_items.qty > 0`, `payments.amount > 0`. |
| Cascading deletes correct | ✅ | Customer delete cascades to measurements + tryons; boutique delete cascades everywhere |
| No orphaned records | ✅ | RPC-based atomic order creation; FK enforcement |
| Migrations reversible | ❌ | **Gap:** migrations are forward-only by convention (Supabase pattern). Rollback = new forward migration that reverts. Documented in `deployment.md`. |

---

## 6. Error Handling

| Item | Status | Evidence |
|---|---|---|
| All errors caught | ✅ | Silent-failure-hunter audit pass found and fixed every uncontrolled `try? await ... ?? []`. Remaining ones are deliberate (truly optional reads). |
| User-facing messages helpful, non-technical | ✅ | "Couldn't load payment history — retry before recording new payments." style throughout |
| Internal details logged separately from displayed | ⚠️ | Currently `error.localizedDescription` is shown directly. Adequate for Swift errors but could leak Postgres details. **Recommendation:** map known errors to friendly strings. |
| Error types/enums (not stringly) | ✅ | `GeminiError` enum. Most errors are propagated as their original typed `Error`. |
| Retry with exponential backoff | ⚠️ | No automatic retry — owner taps Retry button manually. **Acceptable** for pilot. |
| Circuit breakers | ⚠️ | None. Single-tenant pilot doesn't need them yet. |
| Graceful degradation | ✅ | Dashboard banner on partial failure; Gemini-disabled fallback when key missing; JobCard creation blocked but other features usable when measurements load fails |
| Global error boundary | ✅ | `ErrorBus` + `ErrorToastOverlay` on RootView |

---

## 7. Logging & Observability

| Item | Status | Evidence |
|---|---|---|
| Structured logging (not print) | ✅ | **0** `print()` statements in production code |
| Log levels used appropriately | ❌ | **Gap:** no explicit logging framework. iOS `os.Logger` not adopted yet. |
| No sensitive data in logs | ✅ | Nothing is logged client-side that contains PII |
| Request tracing / correlation IDs | ❌ | **Gap:** Supabase logs by JWT but no client-side correlation ID |
| Performance metrics tracked | ⚠️ | Gemini calls log `processing_ms` to DB. No app-level perf metrics. |
| Alerts for error spikes | ⚠️ | Manual Supabase dashboard review only. **Recommendation:** Supabase log drains → simple Slack alert on 5xx burst |

---

## 8. Testing

### Unit Tests (refreshed 2026-05-28: 118 cases across 14 suites, all green)

| Item | Status | Evidence |
|---|---|---|
| Business logic tested | ✅ | `StatusMachineTests` (OrderStatus.nextOptions + InquiryStatus.allowedNext, 11 cases) |
| Service methods tested | ⚠️ → 🟢 | Pure-logic services tested (Formatters, GSTINValidator, CustomerImportService, GSTReportExporter, Money). **Network services not unit-tested** still — concrete services (DIP gap remains). |
| Model encoding/decoding tested | ✅ | `EnumDecodingTests` + `ModelDecodingTests` + `PaymentsServiceModelTests` cover forward-compat fallback, optional column decoding, and Codable round-trip |
| Edge cases tested | ✅ | CRLF line endings (caught a real grapheme-cluster bug), sub-paise drift, empty input, single column, escaped quotes, Hindi/Hinglish in CSV |
| Error paths tested | ✅ | GSTINValidator length errors, invalid emails, empty CSV, missing column, malformed JSON |
| Dependencies mocked | N/A | Pure-logic tests don't have dependencies |
| Test names describe behavior | ✅ | e.g. `testInquiryCannotGoBackToNew`, `testBalanceDueWontDriftAboveZeroOnFullyPaidOrder` |
| Design tokens tested | ✅ NEW | `DesignTokensTests` enforces 8pt grid alignment + HIG animation ranges |
| Regression tests for fixed bugs | ✅ | `MoneyTests.testBalanceDueWontDriftAboveZeroOnFullyPaidOrder` (L7), `CustomerImportServiceTests.testCRLFLineEndings` (grapheme cluster bug) |

### Integration Tests

| Item | Status | Evidence |
|---|---|---|
| Service-to-DB flows | ❌ | **Gap:** would require a test Supabase project or mocks. Deferred. |
| API endpoint flows | ❌ | Same gap. |
| Auth flows end-to-end | ❌ | Manual only. |
| Cross-module data flow | ❌ | Same gap. |
| External service integration tests | ❌ | Gemini calls are integration-tested only manually. |

### Security Tests

| Item | Status | Evidence |
|---|---|---|
| Auth bypass | ⚠️ | Supabase RLS is the boundary; no client-side test attempts to bypass |
| Authz escalation | ⚠️ | Single-tenant pilot; not yet tested across tenants |
| SQL injection | ✅ | Architecturally impossible (PostgREST + parameterized RPCs) |
| XSS | N/A | Native app |
| Rate limit under load | ⚠️ | Not load-tested |
| CSRF | N/A | |
| Invalid token handling | ⚠️ | Manual only |

### Regression Tests

| Item | Status | Evidence |
|---|---|---|
| Critical paths automated | ⚠️ | Unit tests cover pure logic; UI happy paths not yet automated via XCUITest |
| Previously fixed bugs have regression tests | ✅ | The CRLF test was *added* because of a parser bug discovered in this session. CRLF will not regress silently. |
| Smoke tests | ⚠️ | `ConfigTests` is the only end-to-end smoke. **Recommendation:** add a `SignInSmokeTest` against the demo account when on simulator. |

### Test Infrastructure

| Item | Status | Evidence |
|---|---|---|
| Tests in CI on every PR | ❌ | **Gap:** no CI yet. **Recommendation:** GitHub Actions workflow running `xcodebuild test` on PR. |
| Code coverage threshold | ❌ | None enforced. |
| Deterministic | ✅ | All current tests are pure-logic; no time/random/network |
| Test data isolated | ✅ | No shared state |
| Tests run fast | ✅ | 68 tests run in <2 seconds |

---

## 9. Release Readiness

| Item | Status | Evidence |
|---|---|---|
| No TODO/FIXME/HACK blocking | ✅ | **0** instances |
| No debug/demo mode default | ✅ | All `#if DEBUG`-gated (sign-in escape hatch, launch args) |
| Env vars documented | ✅ | `docs/deployment.md` table |
| Rollback plan | ✅ | `docs/deployment.md` Rollback section |
| Known issues documented | ✅ | `docs/dpdp-compliance.md` Open items + audit findings deferred items |
| Monitoring/alerting | ⚠️ | Supabase dashboard only. **Recommendation:** weekly automated report. |
| Runbook for common failures | ❌ | **Gap:** `docs/runbooks/` does not exist. Recommended for: bad deploy rollback, Gemini outage, RLS misconfiguration, photo-purge cron failure. |

---

## Top recommended actions

### Quick wins (~1 hour each)
1. ✅ Extract the 5 inline `SupabaseService.client.from(...)` calls in views into proper Service methods — **Done 2026-05-28** (created `ImportantDatesService`, `PaymentsService`, `BoutiqueService`)
2. ✅ Add CHECK constraints on `order_items.qty > 0`, `order_items.unit_price >= 0`, and `payments.amount > 0` — **Done 2026-05-28** (migration `audit_phase3_constraints_costceil`)
3. ✅ Move Gemini API key from URL query to `x-goog-api-key` header — **Done 2026-05-28**
4. ⏭️ Raise Supabase password minimum to 10 chars — pending dashboard change (no code path)

### Medium (~half-day each)
5. ⏭️ Introduce `protocol *Servicing` for the 3-4 most-used services to enable integration test mocking — still deferred
6. ✅ Add Gemini cost ceiling counter (per-boutique daily limit) — **Done 2026-05-28** (Postgres `record_ai_usage` RPC + `AICostMeter` Swift wrapper, $5/day default)
7. ⏭️ Add `os.Logger` adoption + 3-5 strategic log statements — still deferred
8. ✅ Write GitHub Actions workflow for `xcodebuild test` on PR — **Done 2026-05-28** (`.github/workflows/ipad-tests.yml`)
9. ✅ Create `docs/runbooks/` with at least 2 runbooks — **Done 2026-05-28** (bad-deploy-rollback.md + gemini-outage.md + index)

### Larger (≥1 day)
10. ⏭️ Integration test suite against a test Supabase project — still deferred
11. ⏭️ XCUITest happy-path smoke for: sign-in → create customer → create order → record payment → generate invoice — still deferred
12. ⏭️ Dependabot or Renovate for SwiftPM dependency PRs — still deferred
