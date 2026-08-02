# Template Adherence Register

**Date:** 2026-07-31
**Covers:** the iPad app, Supabase backend, and Edge Functions, after R4a/R4b.
**Sources:** eleven checklists — Accessibility, Apple Design Framework
(Complete Standard v1.0), Content & Localization, Documentation, Performance &
Reliability, Post-Launch Operations, Release & App Store Submission, Security
& Privacy, Sync & Multi-Device, Upgrade Path, and Software Testing & Code
Quality.

**Method:** each section audited against the code, not against intent. Claims
name a file, line, or query. **Nothing is ✅ on the strength of intent** — a
control that exists but is unproven is ⚠️; one that does not exist is ❌, even
where its absence is a deliberate decision.

Fixes applied during this audit are marked **[fixed]** and listed in §Fixes.

---

## Security & Privacy Checklist

### §1 Data inventory & minimization
| Item | | Evidence |
|---|---|---|
| Every piece of personal data listed | ✅ | `docs/DATA_HANDLING.md`, `docs/privacy-policy.md` |
| Each item has a reason to exist | ✅ | Reason column in the privacy-policy inventory |
| Sensitive identifiers optional | ✅ | GSTIN optional (invoices disable without it); DOB/measurements optional |
| Nothing collected "just in case" | ✅ | No location, contacts, device ID, or analytics |

### §2 Storage & encryption
| Item | | Evidence |
|---|---|---|
| Sensitive data encrypted at rest | ✅ | Supabase-managed encryption; iOS Data Protection for the Keychain |
| Secrets in a secure store, never plaintext config | ✅ | `Services/KeychainStore.swift`; PIN as salted hash only |
| No PII in logs | ✅ | Verified: every person-data log uses `privacy: .private` (`AuthService.swift:38,44`; `Log.swift:54`) |
| Sensitive views gated behind auth/biometric/re-auth | ⚠️ | R4b gates money surfaces behind a PIN — but it is UI-only, not authorization (`SECURITY_REVIEW.md` §1) |
| Backups don't leak sensitive data | ✅ | PIN + role use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (backup-excluded) |

### §3 Data in transit
| Item | | Evidence |
|---|---|---|
| HTTPS/TLS only | ✅ | All Supabase + Gemini endpoints HTTPS; no `http://` endpoints in source |
| No PII in URL query parameters | ✅ | Gemini key moved to `x-goog-api-key` header (`GeminiService.swift:172,203`); karigar page uses an opaque token, not customer data |
| Certificate pinning considered | ❌ | Not implemented. Considered and deferred; recorded, not silently skipped |
| Modern TLS, no deprecated ciphers | ✅ | Platform URLSession defaults |

### §4 Secrets management
| Item | | Evidence |
|---|---|---|
| No credentials in source | ✅ | `git ls-files` returns only `Secrets.xcconfig.example` |
| No credentials in version-control history | ⚠️ | Not scanned. No secret-scanning tool has been run over history |
| Secrets loaded from env/secret manager | ✅ | `Config.swift` reads xcconfig; not hardcoded |
| Different credentials per environment | ❌ | **One Supabase project serves dev and prod** — there is no separate environment |
| Keys rotatable without a client release | ❌ | Gemini key is client-embedded; rotation needs a release |
| Client-embedded keys assumed public | ✅ | Anon key is RLS-protected by design; documented as safe to ship |

### §5 Permissions & access requests
| Item | | Evidence |
|---|---|---|
| Only permissions it uses | ✅ | Camera, Photo Library, Photo Add, Face ID — four, all used |
| Every permission maps to a reachable feature | ✅ | `NSFaceIDUsageDescription` added with R4b's device-auth recovery, which ships in this release |
| Rationale strings specific and honest | ✅ | `Info.plist:53–60` name the actual use, e.g. Face ID "to restore owner mode when the assistant PIN is locked out" |
| Degrades gracefully when denied | ⚠️ | Camera/photo denial paths not explicitly tested |

### §6 Authentication & access control
| Item | | Evidence |
|---|---|---|
| Auth correct for the model | ✅ | Supabase magic-link (OTP); no passwords in prod |
| Passwords hashed with bcrypt/scrypt/Argon2 | N/A → ⚠️ | No account passwords. The **PIN** uses salted SHA-256, not a slow KDF — deliberate and argued in `SECURITY_REVIEW.md` §3, but it is a deviation from the letter of this item |
| **Authorization checked server-side on every privileged action** | ❌ | **The R4b role gate is client-side only.** RLS scopes by boutique, not by staff role |
| Data isolation enforced **and tested** | ⚠️ | RLS on 40/40 tables — but the isolation test is manual, not automated. Three tables shipped with dead policies (fixed, migration 0031) |
| Role-based access enforced where roles exist | ❌ | Same as above — UI-only |
| Session/token expiry + refresh rotation; failed-login rate limiting | ⚠️ | Supabase handles session refresh and auth rate limits. **PIN** attempts are rate-limited locally (lockout + hard cap) |

### §7 Third-party SDKs & dependencies
| Item | | Evidence |
|---|---|---|
| No analytics/tracking/ads SDKs | ✅ | Verified: no Firebase/Amplitude/Mixpanel/Sentry anywhere |
| Each dependency's data collection known | ✅ | One runtime dependency: supabase-swift |
| Dependencies scanned for vulnerabilities | ❌ | No Dependabot/Snyk/SCA |
| Lockfile committed | ✅ | SPM resolved file in the Xcode project |

### §8 AI / LLM privacy
| Item | | Evidence |
|---|---|---|
| **User content redacted of PII before being sent to a model — and the redaction actually wired in** | ✅ **[fixed]** | Was ❌ — nothing was redacted. Now `Utilities/AISafety.redactPII` (phone/email/GSTIN/PAN/Aadhaar), applied **inside the prompt builder** (`GeminiService.tailorBrief`) so a new caller cannot forget. Customer name/phone/email/address were never sent |
| Cloud AI opt-in and off by default | ⚠️ | AI is core to the product, not an add-on. It is credential-gated (`Config.aiEnabled`) and every render is owner-initiated, but it is not "off by default" in the checklist's sense |
| **Model output sanitized before display or storage** | ✅ **[fixed]** | Was ❌ — only whitespace-trimmed. Now `AISafety.sanitizeModelOutput` strips control characters and caps length before the text reaches a PDF, a jsonb column, and the karigar's HTML page |
| **Prompt-injection surface minimized** | ✅ **[fixed]** | Was ❌ — free-text notes were interpolated raw. Now injection markers are stripped and the prompt's own `-----` fences are neutralised so user text cannot close the data section |
| Token/cost limits enforced per user | ✅ | `AICostMeter.checkCeiling` at both chokepoints (`GeminiService.swift:165,196`), enforced server-side via `record_ai_usage` |

### §9 Privacy policy & store disclosure
| Item | | Evidence |
|---|---|---|
| Privacy policy exists | ✅ | `docs/privacy-policy.md` |
| Published at a stable URL, linked in listing + in-app | ❌ | Not hosted; no in-app link |
| Policy describes actual data flows | ✅ **[fixed]** | Was ⚠️ — it omitted the karigar, assistant mode, reminder log, and WIP photos. Corrected 2026-07-31 |
| Store disclosure matches reality | ⚠️ | Answers prepared in `docs/DATA_HANDLING.md`; not yet submitted |
| Encryption export compliance answered | ❌ | Not yet answered |

### §10 Regulatory
| Item | | Evidence |
|---|---|---|
| Applicable law considered | ✅ | India DPDP 2023 — `docs/dpdp-compliance.md` |
| Lawful basis / consent obtained | ✅ | Explicit consent timestamped **before** the Gemini call; enforced centrally in `CustomerNotifier` |
| Children / age-gating | N/A | Not directed at children; the only users are boutique staff |
| Cross-border transfer handled | ⚠️ | Data resident in Mumbai (ap-south-1), but **Gemini calls leave India**. Disclosed in the privacy policy; no transfer-impact assessment done |

### §11 Deletion & retention
| Item | | Evidence |
|---|---|---|
| User can delete their data; deletion actually deletes | ❌ | **No in-app customer-deletion flow exists.** The privacy policy promises deletion on request; today that is a manual database operation. `orders.customer_id` is `ON DELETE RESTRICT`, so a customer with orders cannot be deleted at all without handling the orders first |
| No orphaned records/files after deletion | ⚠️ | FK cascades are configured (100 FKs), but **storage objects are not cascaded by the database** — deleting a row does not delete its bucket object except via the purge function |
| User can export their data | ❌ | No per-customer data export. `GSTReportExporter` is for statutory filing, not portability |
| Retention limits defined and enforced | ⚠️ | 7-day try-on purge enforced by cron (verified running); other retention is policy-only, enforced manually |

### §12 Hardening & incident readiness
| Item | | Evidence |
|---|---|---|
| Input validation / output encoding against injection | ✅ **[fixed]** | Was ❌ — three unescaped interpolations on the **unauthenticated** karigar page (`job-card-view/index.ts:130,136,140`). The `as Record<string, number>` cast is compile-time only and `f: any` guarantees nothing, so jsonb content reached HTML unescaped. All now escaped; `esc()` also hardened to escape `'` |
| Error responses don't leak internals | ✅ **[fixed]** | Was ❌ — raw Gemini error bodies (which can carry key fragments and internal status strings) were shown to the owner. Now `AISafety.userFacingAIError` logs the body `.private` and shows an actionable message |
| Audit logging for security-relevant actions | ⚠️ | Role transitions logged; best-effort and not tamper-evident |
| You know what a compromise would expose | ✅ | `SECURITY_REVIEW.md` §1 states it plainly |

---

## Software Testing & Code Quality Checklist

### §1 Code quality & architecture
| Item | | Evidence |
|---|---|---|
| SOLID / single responsibility | ✅ | Stateless service enums, one per resource; pure engines separated from views |
| DRY — shared utilities, single source of truth | ✅ | `Formatters`, `DesignTokens`, `Money`, `AISafety`; consent centralised in `CustomerNotifier` |
| Dead code — no unused imports, commented-out blocks, "legacy just in case" | ✅ | Verified: no `TODO`/`FIXME`/`HACK` blocking, no commented-out code blocks, no orphan files |
| Architecture layering — views never call the data layer | ✅ | Verified: zero `SupabaseService.client` references in `Features/` |
| No circular dependencies | ✅ | Services do not import Features |

### §2 Input validation & sanitization
| Item | | Evidence |
|---|---|---|
| Text inputs validated for length/format | ⚠️ | GSTIN structure **+ mod-36 check character** (`GSTINValidator`; checksum added 2026-08-01 — it was structure-only before, which is how a placeholder GSTIN reached production invoices), phone normalised, PIN validated. **Free-text fields (notes, descriptions) have no length cap** before hitting the DB |
| Numeric inputs bounded | ⚠️ | Money uses paise rounding + breakup reconciliation; no explicit min/max on every numeric field |
| File uploads validated for type, size, content | ✅ | `job-card-view/index.ts:76–84` — 5 MB cap, JPEG/PNG allow-list, extension derived from validated MIME (not the filename), UUID filename |
| SQL injection prevented (parameterized only) | ✅ | PostgREST/RPC parameter binding throughout; no string-concatenated SQL |
| XSS prevented by encoding HTML output | ✅ **[fixed]** | See Security §12 |
| Path traversal prevented | ✅ | Upload paths are `${card.id}/${crypto.randomUUID()}.${ext}` — no user-controlled path segment |
| Rate limiting on expensive operations | ✅ | Karigar page: 30/day/card. AI: server-side cost ceiling |
| AI content sanitized in and out | ✅ **[fixed]** | See Security §8 |
| Concurrency — async awaited, cancellation, state captured at invocation | ⚠️ | Swift structured concurrency throughout, `@MainActor` on contexts. **Not systematically audited** for capture-at-invocation |
| Resource cleanup — tasks cancelled on teardown | ⚠️ | SwiftUI `.task` cancels on disappear; no manual audit of observers/timers |

### §5 Database & data integrity
| Item | | Evidence |
|---|---|---|
| Parameterized statements | ✅ | As above |
| Indexes on commonly-queried columns | ✅ | 100 indexes across 40 tables |
| N+1 patterns avoided | ✅ | Dashboard/board batch-fetch into dictionaries keyed by id |
| Large result sets paginated | ⚠️ | Lists use `.limit(...)`; no cursor pagination — acceptable at single-boutique scale, unproven beyond it |
| FK constraints enforced | ✅ | 100 FKs |
| Check constraints for valid ranges | ✅ | 260 check constraints |
| Cascading deletes configured correctly | ✅ | Cascade by default; `orders.customer_id` deliberately RESTRICT |
| **Migrations are reversible** | ❌ | Forward-only by design, one shared database. Stated with its consequences in `docs/RELEASE_CHECKLIST.md` §8 |

### §6 Error handling
| Item | | Evidence |
|---|---|---|
| All errors caught and handled | ✅ | The systemic `try?`-swallowing anti-pattern was removed in an earlier audit |
| User-facing messages helpful and non-technical | ✅ **[fixed]** | AI errors were raw upstream bodies; now actionable copy |
| Internal detail logged, not exposed | ✅ **[fixed]** | `AISafety.userFacingAIError` logs `.private` |
| Error types/enums used, not string errors | ✅ | `GeminiError`, `DispatchError`, typed `PostgrestError` handling in `RemindersService` |
| Retry with backoff for transient failures | ❌ | Retry is manual (user taps Retry). No automatic backoff |
| Circuit breakers for external calls | ❌ | None |
| Graceful degradation when dependencies are down | ✅ | `MorningBoard` degrades per-input; `ReminderDrafts` suppresses rather than guessing |
| Global error boundary | ✅ | `ErrorBus` |

### §7 Logging & observability
| Item | | Evidence |
|---|---|---|
| Structured logging, no `print` | ✅ | Verified: zero `print(` in the app target; `os.Logger` with categories |
| Log levels used appropriately | ✅ | `.info`/`.notice`/`.error` per site |
| No sensitive data in logs | ✅ | `privacy: .private` on all person data |
| Request tracing / correlation IDs | ❌ | None |
| Performance metrics tracked | ❌ | None |
| Alerts configured for error spikes | ❌ | None |

### §8 Testing
| Item | | Evidence |
|---|---|---|
| All business logic tested | ✅ | Eight pure engines under test |
| All service methods tested | ❌ | Services are network-bound; **no service-layer tests at all** |
| Model encode/decode tested | ✅ | Codable round-trips |
| Edge cases tested | ✅ | Clock-winding, cap precedence, malformed blobs, degraded inputs, `\r\n` CSV |
| Error paths tested | ⚠️ | Pure-logic error paths yes; network error paths no |
| Test names describe behavior | ✅ | Behavior-style naming throughout |
| **Integration tests** | ❌ | None — no service-to-database, no API request/response, no auth-flow tests |
| **Security tests** (authz escalation, injection payloads) | ❌ | None automated. The role gate has **no test that fails if a gate is deleted** |
| Regression tests for fixed bugs | ⚠️ | Some (LockGate, clock-winding). The dead-RLS bug has **no regression test** |
| Tests run in CI on every PR | ✅ | `.github/workflows/ipad-tests.yml` |
| Code coverage tracked with a threshold | ❌ | Not measured |
| Tests deterministic, isolated, fast | ✅ | 239 tests; ~2s warm |

### §9 Release readiness
Covered under the Release checklist below.

---

## Apple Design Framework

### §1 Ten First Principles
| Principle | | Evidence |
|---|---|---|
| 1 Immediate recognition | ✅ | One primary job per screen; morning board is exception-first |
| 2 Predictable behavior | ✅ | Status transitions via `nextOptions`; destructive actions confirm (`confirmationDialog` on sign-out) |
| 3 Information hierarchy | ✅ | Tiles → needs-you → pipeline; progressive disclosure in sheets |
| 4 Touch-first (≥44pt) | ✅ | `.frame(minHeight: 44)` on all R4a/R4b controls |
| 5 Meaningful motion | ✅ | Only two animation sites app-wide; both honour Reduce Motion (`RootView:18`, `ErrorBus:68` swaps movement for a cross-fade — the recommended treatment) |
| 6 Accessible by default | ⚠️ | Labels on newest surfaces (14 of ~40 Feature files). **Contrast ratios never measured**; VoiceOver never run end-to-end |
| 7 Error prevention | ✅ | Lock gate refuses invalid states; breakup must reconcile; money UI blocked on failed fetch |
| 8 Performance perception | ⚠️ | Loading states present. **No measurement** — see Performance §1 |
| 9 Platform authenticity | ✅ | SF Symbols, `NavigationSplitView`, native Form/Section idioms |
| 10 Graceful degradation | ⚠️ | Degrades honestly when the *server* fails. **No offline mode** — no local cache; the app is unusable without network |

### §2 Visual standards
| Item | | Evidence |
|---|---|---|
| Typography follows the scale | ⚠️ | Text styles used nearly everywhere; **2 fixed-size exceptions** (`DesignsListView:159`, `AppShellView:105`) — decorative empty-state glyphs |
| Semantic colors only, no hex | ✅ | No hardcoded hex in Features |
| Dark mode | ⚠️ | Semantic colors adapt automatically; **never tested** |
| 8pt grid | ✅ | `Spacing` tokens are 4/8/16/24/32 |

### §3–4 Interaction & components
| Item | | Evidence |
|---|---|---|
| Touch targets ≥44pt, 8pt spacing | ✅ | As above |
| Animation durations 200–300ms | ✅ | `AnimationToken.standard` |
| Corner radii 12/16pt | ✅ | `CornerRadius.card = 12`, `cardLarge = 16` |
| Design tokens not hardcoded values | ✅ | `DesignTokens.swift` |

### §5 QA & validation
| Item | | Evidence |
|---|---|---|
| 3-second / squint / grayscale tests | ❌ | Never run — they need a human looking at the screen |
| Contrast ≥4.5:1 measured | ❌ | Never measured |
| VoiceOver tested | ❌ | Never run |
| Dark mode tested | ❌ | Never tested |
| Empty / loading / error states designed | ✅ | All three exist on the newest surfaces |

---

## Content & Localization Checklist

| § | Item | | Evidence |
|---|---|---|---|
| 1 | Consistent voice, no dev jargon | ✅ | Plain-language copy; Hinglish where the karigar reads it |
| 2 | Action-verb CTAs | ✅ | "Send on WhatsApp", "Mark done", "Hand over to assistant" |
| 2 | Confirmations state the consequence | ✅ | "You'll need your email to sign back in" |
| 3 | Empty states explain what goes here | ✅ | Reminders: "fittings, balances, and ready orders will appear here" |
| 3 | Loading copy honest and brief | ✅ | "Checking reminders…" |
| 3 | Errors non-technical and actionable | ✅ **[fixed]** | AI errors now name the fix; PIN errors name the problem, never the value |
| 3 | Disabled actions say why | ⚠️ | Invoice button explains the missing GSTIN; **not universal** — some disabled buttons are silent |
| 4 | One term per concept | ✅ | karigar / owner / assistant used consistently |
| 5 | Currency per locale | ✅ | `Formatters.inr` with `en_IN` lakh grouping; never hand-formatted |
| 5 | Dates/times correct zone | ✅ | `Formatters.postgresDate` (POSIX + Asia/Kolkata) |
| 5 | Pluralization via real rules | ✅ | "1 reminder" / "2 reminders", never "reminder(s)" |
| 5 | Numeric precision for money | ✅ | `Money.roundedToPaise`, `equalAtPaise` — never `Double ==` |
| 6 | **No hardcoded user-facing strings** | ❌ | **Zero** `.xcstrings`/`.strings`/`.stringsdict`. All copy is inline English literals |
| 6 | Text fits at largest accessibility size | ⚠️ | `minimumScaleFactor` on the revenue figure; not verified at AX5 |
| 6 | RTL | N/A | No RTL target locale |
| 7 | Screen-reader labels meaningful | ⚠️ | Composite rows labelled on newest surfaces; older screens unaudited |
| 7 | Status conveyed by more than color | ✅ | Status pills pair color with a text label and SF Symbol |
| 8 | Store/legal copy accurate | ⚠️ | Privacy policy accurate as of today; **store listing not written** |
| 9 | No placeholder copy shipped | ⚠️ | Verified none in Swift. **`docs/privacy-policy.md` still contains `[TO BE FILLED IN]`** — blocks submission |

---

## Performance & Reliability Checklist

| § | Item | | Evidence |
|---|---|---|---|
| 1 | Startup fast, measured | ❌ | Never measured |
| 1 | No heavy work blocking startup | ✅ | `.task` loads after first render; skeleton/ProgressView shown |
| 2 | Smooth scroll, no jank | ❌ | Never profiled |
| 2 | Lazy loading for long lists | ⚠️ | SwiftUI `List` virtualizes; long-list behaviour untested at scale |
| 2 | Images sized to display size | ⚠️ | Signed-URL images loaded at source resolution; no downsampling for thumbnails |
| 3 | No leaks / retain cycles | ❌ | Never profiled |
| 3 | Caches bounded | N/A | No custom cache layer |
| 4 | No busy-wait / runaway timers | ✅ | One 1s timer in `PinEntrySheet`, scoped to the sheet's lifetime |
| 4 | Requests batched, retried with backoff | ⚠️ | Batched via dictionaries; **no automatic retry/backoff** |
| 5 | Hot queries efficient, indexed | ✅ | 100 indexes |
| 5 | N+1 avoided | ✅ | Batch fetch + dictionary join |
| 6 | No blocking calls on main thread | ✅ | `async/await` throughout; services are non-isolated |
| 6 | Shared mutable state protected | ✅ | `@MainActor` on both context objects; services stateless |
| 7 | Crash-free target defined and monitored | ❌ | No crash reporting at all |
| 7 | Data integrity under interrupted writes | ✅ | Atomic RPCs for every multi-row write |
| 8 | No debug resources in the release artifact | ✅ | Demo sign-in `#if DEBUG` |
| 9 | Reduced motion honoured everywhere | ✅ | Both animation sites; verified exhaustively (only two exist) |
| 9 | Largest text doesn't break layout | ⚠️ | Not verified |
| 10 | **Profiler pass on a real target** | ❌ | **Never done.** No Instruments run, no low-end device test |

---

## Documentation Checklist

| § | Item | | Status |
|---|---|---|---|
| 1 | [R] README.md | ✅ | Present, current |
| 1 | [R] CLAUDE.md | ✅ | Refreshed with this change |
| 1 | [+] CONTRIBUTING.md | ❌ | Absent |
| 1 | [R] LICENSE | ✅ | Proprietary, © 2026 Ateeshay Jain |
| 1 | [+] CHANGELOG.md | ✅ | Entry per release |
| 1 | [+] STATE.md / STATUS.md | ❌ | Absent (README carries some of this) |
| 2 | [R] ARCHITECTURE.md | ✅ | `docs/architecture.md` + C4 diagrams |
| 2 | [+] DATA_MODEL.md | ⚠️ | Covered inside `architecture.md`, not a standalone doc |
| 2 | [+] SCREENS.md | ✅ | `docs/app-map.md` |
| 2 | [~] SETUP.md | ⚠️ | Build/run steps in README; no dedicated setup doc |
| 3 | [+] PERSONAS / PROBLEM_STATEMENTS | ❌ | Absent |
| 3 | [+] USER_JOURNEYS / [o] USER_FLOWS | ✅ | `docs/user-journeys.md`, `docs/user-flows.md`, `docs/customer-journey-3-month.md` |
| 3 | [+] ROADMAP.md | ✅ | Roadmap table in `docs/app-map.md` |
| 4 | [+] BRAND.md | ❌ | Absent — tokens exist in code, no doc |
| 5 | [R] QA_CHECKLIST.md | ❌ | **Absent.** Manual QA steps live inside plan files, not a standing document |
| 5 | [+] TEST_RESULTS.md | ❌ | Absent (counts in CHANGELOG) |
| 5 | [+] ACCESSIBILITY_AUDIT.md | ❌ | Absent — and no audit has been run |
| 5 | [+] AUDIT_FINDINGS.md | ✅ | `audit-outputs/` |
| 5 | [~] SECURITY_REVIEW.md | ✅ | Trigger met (PII + payments); written 2026-07-31 |
| 6 | [R] PRIVACY_POLICY.md | ⚠️ | Exists and accurate; placeholders unfilled, not hosted |
| 6 | [R] DATA_HANDLING.md | ✅ | Written 2026-07-31 |
| 6 | [R] RELEASE_CHECKLIST.md | ✅ | Written 2026-07-31 |
| 6 | [~] THIRD_PARTY_LICENSES.md | ❌ | Trigger met (supabase-swift bundled); absent |
| 6 | [~] TERMS_OF_SERVICE.md | N/A | No customer accounts or UGC |
| 7 | [R] Spec + Plan per feature | ✅ | `docs/superpowers/specs/`, `plans/` |
| 8 | [~] CI.md | ⚠️ | Workflow is self-documenting; no CI.md |
| 8 | [~] DEPLOYMENT.md | ✅ | `docs/deployment.md` |
| 8 | [~] RUNBOOK.md | ⚠️ | `docs/runbooks/` exists; **no RLS-verification runbook** |

---

## Release & Store Submission Checklist

| § | Item | | Evidence |
|---|---|---|---|
| 1 | Version bumped | ⚠️ | Still `0.1.0` / build 1 — bump at release |
| 2 | No QA/debug flag enabled | ✅ | Demo sign-in `#if DEBUG` (`SignInView:95,120`) — **must still be confirmed in a Release build** |
| 2 | Build points at production | ✅ | One project; dev and prod are the same |
| 2 | Logging level appropriate | ✅ | `os.Logger`, nothing leaves the device |
| 3 | Migrations deployed to production | ✅ | 35 applied |
| 3 | Prod credentials rotated from dev values | ❌ | No separation exists to rotate between |
| 4 | Signing with production credentials | ⚠️ | Not yet exercised |
| 4 | Debug symbols archived | ⚠️ | Not yet |
| 5 | Privacy policy URL live | ❌ | Not hosted |
| 5 | Store data disclosure submitted | ❌ | Answers ready, not submitted |
| 5 | Export compliance answered | ❌ | Not answered |
| 5 | Age rating set | ❌ | Not set |
| 6 | **Listing assets** — name, description, keywords, screenshots, icon | ❌ | **Not started** |
| 7 | Reviewer notes + demo path | ❌ | Not written. **Needed** — the app is behind a magic-link login, so a reviewer cannot get in without instructions |
| 8 | Release build, no warnings, no test code | ⚠️ | Builds clean; Release config not exercised |
| 9 | Fresh-install QA | ❌ | Not done |
| 9 | Accessibility spot-check | ❌ | Not done |
| 9 | Automated suite green in CI on the release commit | ✅ | 239 tests |
| 10 | Staged rollout via TestFlight | ❌ | Not started |
| 11 | Tag the release | ❌ | No tags yet |
| 12 | Rollback path known | ✅ | `docs/RELEASE_CHECKLIST.md` §8 — app rollback cheap, migrations effectively irreversible |
| 12 | Monitoring watched post-release | ❌ | No crash/error monitoring exists |

---

## Accessibility Checklist  *(added 2026-08-01)*

The most demanding of the eleven, and the one this project scores worst on.
The checklist's own framing is the reason: *"Accessibility failures are
invisible to the people who build the app and total to the people they
exclude."* Nothing here has been tested with a screen reader or a contrast
meter — the ✅ rows are code-level facts, not evidence of use.

### §1 Contrast
| Item | | Evidence |
|---|---|---|
| Text ≥4.5:1 (3:1 for large) | ❌ | **Never measured.** Semantic colours make it *likely* — that is not evidence |
| Non-text UI ≥3:1 | ❌ | Never measured. Status pills, slack badges and pipeline lanes carry meaning by colour |
| Verified in BOTH appearances, programmatically | ❌ | No contrast assertion exists; dark mode never opened |
| Filled elements use PAIRED foreground colours | ✅ | Verified: **zero** `foregroundStyle(.white)` in `Features/` — no hardcoded white on a brand colour, which is one of the checklist's stop-the-release flags |
| Text over images has a scrim | N/A | No text over imagery |

### §2 Dynamic Type
| Item | | Evidence |
|---|---|---|
| Busiest three screens at AX5 | ❌ | Never exercised at any accessibility size |
| Semantic styles, fixed sizes listed with a reason | ⚠️ | Two fixed sizes, both decorative empty-state glyphs: `DesignsListView:159`, `AppShellView:105` |
| `minimumScaleFactor` floor ≥0.7 | ✅ **[fixed]** | Was ❌ — `DashboardView:122` (revenue total) and `MorningBoardView:70` (tile value) used 0.6. Both are money, which the checklist calls out by name: "shrinking a total is losing the total." Raised to 0.7 |
| Numbers users act on stay readable at AX | ⚠️ | Floor is now compliant; **not verified at AX5** |
| Container heights not hardcoded | ✅ | No fixed-height containers around text |

### §3 Touch targets
| Item | | Evidence |
|---|---|---|
| Every tappable ≥44×44pt incl. padding | ⚠️ | True on all R4a/R4b surfaces (`.frame(minHeight: 44)`); older screens unaudited |
| Destructive actions spaced or confirmed | ✅ | Sign-out uses `confirmationDialog` |
| **Multi-button rows use per-button styles** | ✅ | **Checked specifically** — the reminders row has two buttons and each carries its own `.buttonStyle(.bordered)` (`RemindersSectionView:92,102`), so one tap fires one action. This is the failure the checklist warns produces "every tap fires all of them" |
| Gestures have button equivalents | ✅ | No long-press-only or swipe-only actions |

### §4 Screen reader
| Item | | Evidence |
|---|---|---|
| Icon-only controls labelled by what they DO | ⚠️ | New surfaces yes ("Dismiss — don't ask again"); older screens unaudited |
| Rows read as one sentence | ✅ | `accessibilityElement(children: .combine)` + composed labels on board, orders, reminders |
| Charts expose a text summary | ⚠️ | `CustomerSpendSummaryView` has a Swift Charts bar chart; the KPI tiles carry the numbers, but there is **no explicit chart summary and the chart is not hidden** from the reader |
| Decorative images hidden | ⚠️ | 8 `accessibilityHidden` uses; not systematically audited |
| Custom controls declare traits | ⚠️ | `.isHeader` used; not systematic |
| **One full screen-reader pass per release** | ❌ | **Never run.** VoiceOver has never been used on this app |

### §5 Motion, sound & state
| Item | | Evidence |
|---|---|---|
| Reduce Motion honoured | ✅ | Both animation sites app-wide; `ErrorBus:68` swaps movement for a cross-fade |
| No info by haptic/sound alone | ✅ | No haptic- or audio-only signals |
| Nothing flashes >3×/sec | ✅ | No flashing content |
| Time-limited flows generous | ✅ | Only the PIN cooldown (30s), which is deliberate and displayed |

### §6 Process
| Item | | Evidence |
|---|---|---|
| Contrast assertions in the automated suite, both appearances | ❌ | None |
| New colours enter via tokens with pairings | ⚠️ | `DesignTokens` covers spacing/radius/animation but **not colour pairings**; views use semantic system colours directly |
| A11y findings fixed at functional-bug priority | ⚠️ | Stated here; no track record yet |

**Red-flag status:** two of the five stop-the-release flags are live — a chart
with no textual equivalent, and "looks fine" as the only contrast evidence.

---

## Sync & Multi-Device Checklist  *(added 2026-08-01)*

**Largely N/A by architecture, with one real exception.** There is no
device-to-device sync: a single iPad is the only editing client, and Postgres
is the single source of truth with no local store to reconcile. Most of this
checklist presumes CloudKit-style replication that does not exist here.

The exception is genuine and worth naming: **the karigar's phone is a second
writer.** It POSTs progress events into `job_card_events` through the
`job-card-view` Edge Function while the owner's iPad reads the same rows.

| § | Item | | Evidence |
|---|---|---|---|
| A | Debug and store builds hit different environments | ❌ | **One Supabase project serves both.** Same finding as Security §4 |
| A | Mechanical gate blocks release when prod schema lags | ❌ | No gate. Migrations are applied by hand via MCP |
| A | Deploy step is a named, dated action with an owner | ⚠️ | `RELEASE_CHECKLIST.md` §4 covers it; no owner named |
| A | Schema changes additive with defaults | ✅ | Forward-only, `add column if not exists` throughout |
| A | Every synced field round-trips through a test | ⚠️ | Codable round-trips exist per model; not per field |
| A | Unknown enum values from newer versions degrade safely | ❌ | **Not tested.** `OrderStatus`, `JobCardStatus` etc. would throw on an unknown raw value — a real cross-version risk once two app versions exist |
| B | Conflict policy written per record type | ❌ | Unwritten. Postgres last-write-wins by default |
| B | Concurrently-mintable records use deterministic IDs | ✅ | `next_sequence_value` RPC is race-safe; `reminder_log` has a natural key |
| B | No screen mints a record on appear | ✅ | Records are created on explicit action |
| C | Durable outbox surviving app kill | ❌ | **No offline queue at all** — a failed write is surfaced and lost |
| C | Failures classified transient/conflict/permanent | ⚠️ | Surfaced via `ErrorBus`, not classified; no retry |
| C | Airplane-mode convergence tested | N/A | No offline editing to converge |
| D | Sharing lifecycle (invite/revoke/leave) | N/A | No multi-account sharing |
| E | Two-phone QA matrix | ⚠️ | The one real pair — owner iPad + karigar phone — has **never been exercised together** |
| F | User-reachable re-sync | N/A | Pull-to-refresh re-reads server truth |

**Honest summary:** the architecture sidesteps most sync hazards by having no
local store. What it does *not* sidestep — a second writer on the karigar's
phone, and enum decoding across app versions — is untested.

---

## Upgrade Path Checklist  *(added 2026-08-01)*

**The app has never shipped**, so "upgrade in place" has no history to break
yet. That makes most rows *not yet applicable* rather than passing — and the
checklist's own warning applies: these are exactly the items that are cheap now
and expensive after the first release.

| § | Item | | Evidence |
|---|---|---|---|
| 1 | Versioned local store with a migration plan | N/A | **No local persistence.** No Core Data/SwiftData store; the server is the only store. This removes the entire class of local-migration risk |
| 1 | Aged-data snapshot | N/A | Same reason |
| 2 | Prod schema deployed BEFORE the build needing it | ⚠️ | Practised (migrations applied first) but not gated |
| 2 | New FIELDS re-arm the deploy gate | ❌ | No gate exists to re-arm |
| 2 | App tolerates server knowing LESS | ❌ | **Untested.** A missing column would surface as a decode failure |
| 2 | App tolerates server knowing MORE | ⚠️ | Models decode named keys, so unknown *columns* are ignored — but unknown **enum values** are not (see Sync A) |
| 3 | Unknown enum raw value degrades safely | ❌ | Same gap. This is the single highest-value pre-release fix on this checklist |
| 3 | Version-skew QA pass | ❌ | Not possible yet — no previous release exists |
| 4 | Installable archive of the previous release | ❌ | None. Worth starting **at the first TestFlight build**, not later |
| 4 | Upgrade matrix over aged data | ❌ | Not yet applicable |
| 5 | Version from ONE source of truth, test-enforced | ❌ | `CFBundleShortVersionString`/`CFBundleVersion` live in `Info.plist`, which **XcodeGen regenerates** — the checklist's "generated files can silently revert version keys" risk applies directly, and no test asserts the built artifact's version |
| 5 | Build number increments every upload | ⚠️ | In `RELEASE_CHECKLIST.md` §2; not automated |
| 5 | Changelog separates user-visible from internal | ⚠️ | `CHANGELOG.md` mixes both |

---

## Post-Launch Operations Checklist  *(added 2026-08-01)*

**Nothing here is in place, because the app has not launched.** Recorded in
full rather than skipped: the checklist exists precisely because these get
deferred until an incident forces them.

| § | Item | | Evidence |
|---|---|---|---|
| 1 | Phased release ON | ❌ | Not configured |
| 1 | Halt criteria decided in advance | ❌ | None written |
| 1 | Rollback story named for the release | ⚠️ | `RELEASE_CHECKLIST.md` §8 names it generally: app rollback cheap, **migrations effectively irreversible** |
| 1 | Server prerequisites verified done | ⚠️ | In the checklist; verified by hand |
| 1 | Previous release archived + installable | ❌ | None |
| 2 | Crash reports checked daily first week | ❌ | **No crash reporting exists at all** — nothing to check |
| 2 | Store reviews triaged on a schedule | ❌ | Not launched |
| 2 | In-app failure surfaces treated as monitoring | ⚠️ | `ErrorBus` + stale-data banner exist; nobody is watching them |
| 2 | First-48-hours smoke pass on a production install | ❌ | Not defined |
| 3 | Severity ladder written down | ❌ | None |
| 3 | Known-issue communication path | ❌ | None |
| 3 | Expedited-review criteria known | ❌ | Not researched |
| 3 | Post-incident → checklist line or test | ⚠️ | Practised in this session (RLS defect → CLAUDE.md landmine + register row); not a standing rule |
| 4 | Support channel real and monitored | ❌ | **Not established.** The privacy policy's contact fields are still placeholders |
| 4 | Diagnostic playbooks for top three symptoms | ⚠️ | `docs/runbooks/` covers bad deploy + Gemini outage; nothing for "invoice won't generate" or "AI says limit reached" — the two most likely real reports |
| 4 | User can produce diagnostics unaided | ⚠️ | Settings shows app version + Supabase host; no export |
| 5 | Confirmed bug → regression test before the fix ships | ⚠️ | Followed for pure-logic bugs; **the three RLS defects have no regression test** because nothing tests RLS |
| 6 | Schema-deploy runbook executable at midnight | ⚠️ | `RELEASE_CHECKLIST.md` §4 + `deployment.md`; not rehearsed |
| 6 | Export/backup verified working every release | ❌ | GST CSV export exists; no verification step |
| 6 | Deletion paths re-verified each release | ❌ | **No deletion path exists** (Security §11) |
| 6 | Privacy labels re-read when a data type is added | ⚠️ | Done this session; not a standing step |

**The one that matters most:** no crash reporting. Ship without it and the
first week's evidence is whatever the owner happens to mention.

---

## Fixes applied in this audit

| # | Finding | Severity | Fix |
|---|---|---|---|
| 1 | Three unescaped interpolations rendered jsonb content into HTML on the **unauthenticated** karigar page | **High** — stored XSS on a public page | Escaped all three; `esc()` now also escapes `'` (`job-card-view/index.ts:130,136,140,181`) |
| 2 | No PII redaction before sending free text to Gemini | **High** — customer notes left India unredacted | `AISafety.redactPII`, applied inside the prompt builder |
| 3 | Model output not sanitized before PDF / DB / HTML sinks | Medium | `AISafety.sanitizeModelOutput` — control chars stripped, length capped |
| 4 | Free-text notes interpolated raw into the prompt | Medium | Injection markers stripped; `-----` fences neutralised |
| 5 | Raw Gemini error bodies shown to the owner | Medium — can carry key fragments | `AISafety.userFacingAIError`; raw body logged `.private` |
| 6 | Privacy policy omitted the karigar, assistant mode, reminder log, WIP photos | Medium — undisclosed third-party disclosure | Policy updated |
| 7 | DPDP purge schedule misstated in 7 docs incl. the privacy policy | Low | Corrected to 03:00 IST |

14 tests added for the AI safety layer.

---

## Open findings, ranked

**Blocks release**
1. R4b manual QA (9 steps) never run — blocked on Xcode simulator selection
2. Store listing assets not started; reviewer notes absent (magic-link login makes these mandatory)
3. Privacy policy has `[TO BE FILLED IN]` placeholders and is not hosted
4. Export compliance + age rating unanswered

**High**
4b. **No crash reporting** — ship without it and week-one evidence is whatever the owner happens to mention (Post-Launch §2)
4c. **Unknown enum raw values are not tolerated** — an `OrderStatus` from a newer app version throws on decode. Cheap now, expensive after the first release (Sync A / Upgrade §3)
5. Authorization is client-side only — the role gate is not enforced server-side
6. No customer-deletion flow, despite the privacy policy promising deletion; `orders.customer_id` RESTRICT blocks it for any customer with orders
7. No data-export/portability flow (DPDP right)
9. No security tests: nothing fails if a role gate is deleted
10. No crash reporting or error monitoring

**Medium**
11. No integration or service-layer tests
12. No profiler pass; no measurement of startup, memory, or scroll
13. **Accessibility never audited** — contrast unmeasured in either appearance, VoiceOver never run, dark mode never opened, no AX5 pass. Two stop-the-release flags live: a chart with no textual equivalent, and "looks fine" as the only contrast evidence
13b. No support channel, severity ladder, or halt criteria (Post-Launch §1, §3, §4)
13c. Version is not test-enforced against the built artifact, and XcodeGen regenerates the plist that holds it (Upgrade §5)
13d. Owner iPad + karigar phone have never been exercised as a pair (Sync E)
14. No dependency scanning; git history never secret-scanned
15. Single environment — no dev/prod credential separation
16. No retry/backoff or circuit breakers
17. Storage objects not cascaded on row deletion
18. No RLS-verification runbook; the dead-RLS bug has no regression test

**Low / accepted**
19. No i18n String Catalog (declared)
20. Certificate pinning absent (considered, deferred)
21. Escalating lockout deferred (YAGNI at pilot scale)
22. Audit log not tamper-evident (deliberate)
23. Migrations forward-only (deliberate, with consequences documented)
24. PIN uses salted SHA-256 rather than a slow KDF (argued in `SECURITY_REVIEW.md` §3)

**Owner:** every unassigned item above needs one before submission.
