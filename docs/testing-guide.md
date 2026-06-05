# Testing Guide — Boutique 360

How to write, run, and maintain tests for the iPad app. The current test suite is **pure-logic + Codable round-trip only** — no network, no UI, no flaky timing. That's deliberate: fast (~2s), deterministic, and cheap to keep green.

---

## Running tests

### Locally
```bash
cd ipad
xcodegen generate
xcodebuild -project Boutique360.xcodeproj \
    -scheme Boutique360 \
    -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
    test
```

Filter to a single suite:
```bash
xcodebuild ... test -only-testing:Boutique360Tests/FormattersTests
```

### CI
`.github/workflows/ipad-tests.yml` runs the same command on every PR that touches `ipad/**`. macOS-15 runner, iPad Pro 11" simulator, ~10 minutes end-to-end.

---

## What we test (and what we don't)

### ✅ We test

| Category | Why |
|---|---|
| **Formatters** — INR lakh grouping, IST date round-trip, ISO 8601 precision | Multiple bugs ship from misconfigured locales/timezones; tests pin the behavior |
| **Validators** — GSTIN structural regex, email format, phone normalization | These are pure functions with edge cases; cheap to cover |
| **Parsers** — CSV (RFC 4180), JSON Codable round-trip | The CRLF parser bug was caught by a test the first time it ran; high ROI |
| **State machines** — `OrderStatus.nextOptions`, `InquiryStatus.allowedNext` | Business rules expressed as code; tests document the rules |
| **Money math** — paise rounding, equality at paise | Floating-point math in currency = always tested |
| **Decoding edge cases** — unknown enum values, missing optional columns | Forward-compat decoders must fall back safely; tested via JSON fixtures |
| **Design tokens** — Spacing on 8pt grid, animation in HIG ranges | Adding a 13pt padding will fail CI before merge |

### ❌ We don't (yet) test

| Category | Why deferred | Plan |
|---|---|---|
| Service network calls | Would need test Supabase project + cleanup, OR a mock client | Add when first integration bug ships |
| SwiftUI view rendering | Snapshot tests are flaky on simulator size changes; XCUITest is slow | Add XCUITest happy-path smoke before App Store launch |
| Gemini API integration | Hits real Google service; non-deterministic results | Sandbox/mock when stable test harness exists |
| pg_cron jobs | Postgres-side; tested by smoke-checking via dashboard | OK as-is |
| Edge Function `purge-expired-tryons` | Tested manually + via dashboard logs | Add `deno test` once function gets complex |

The principle: **test the pure logic that's easy to break and easy to test**. Integration tests come when you have enough integration bugs to justify the harness investment.

---

## File layout

```
ipad/Boutique360Tests/
├── ConfigTests.swift                  ← Env.xcconfig loaded
├── CustomerImportServiceTests.swift   ← CSV parser RFC 4180 cases
├── CustomerTimelineEventTests.swift   ← Composite ID Hashable, Set dedup
├── DesignTokensTests.swift            ← 8pt grid + HIG animation ranges
├── EnumDecodingTests.swift            ← Forward-compat fallback
├── ErrorBusTests.swift                ← Toast pipeline contract
├── FormattersTests.swift              ← INR + dates + ISO 8601
├── GSTINValidatorTests.swift          ← Structural validation
├── GSTReportExporterTests.swift       ← RFC 4180 CSV escape
├── ModelDecodingTests.swift           ← Boutique/OrderItem/Order Codable
├── MoneyTests.swift                   ← Paise rounding (regression: L7)
├── PaymentsServiceModelTests.swift    ← Decodable shapes
├── StatusMachineTests.swift           ← OrderStatus + InquiryStatus rules
└── WhatsAppShareHelperTests.swift     ← Phone normalize + URL build
```

---

## How to add a new test

### 1. Pick the right file

| If you're testing… | Add to |
|---|---|
| A new formatter/validator | the relevant existing file (or new `<Thing>Tests.swift`) |
| A new model field | `ModelDecodingTests.swift` |
| A new Codable struct from a Service | `PaymentsServiceModelTests.swift` style — one file per service |
| A new design token | `DesignTokensTests.swift` |
| A new business rule (state transitions) | `StatusMachineTests.swift` |
| A regression for a fixed bug | wherever the rule lives, with a comment referencing the audit ID |

### 2. Use behavior-style test names

✅ `testInquiryCannotGoBackToNew`
✅ `testHinglishMessageEncodes`
✅ `testBalanceDueWontDriftAboveZeroOnFullyPaidOrder`

❌ `testStateMachine1`
❌ `testParseRow`
❌ `test_test_test`

The name should describe **what** the system does, not how.

### 3. Cover the unhappy path

Every happy-path test should be accompanied by at least one of:
- An edge case (empty input, single element, max size)
- A failure case (malformed input, missing field)
- A boundary (off-by-one — first/last position)

### 4. Make the test exposed-private if needed

If the function you want to test is `private`, **change it to internal** (default Swift access) — that's reachable via `@testable import Boutique360`. Don't make it `public` (over-broad). Document the access change with a comment:

```swift
/// `internal` (Swift module-default) so unit tests can reach it via @testable import.
static func csvEscape(_ s: String) -> String { ... }
```

### 5. Extract a testable seam for view logic

If the testable logic is buried in a SwiftUI view (e.g., the `balanceDue` rounding was originally inside `PaymentsSectionView`), extract it into a free function or a utility:

```swift
// Before: trapped inside the view
private var balanceDue: Double { ((order.total - receivedTotal) * 100).rounded() / 100 }

// After: in Utilities/Formatters.swift Money enum
enum Money {
    static func roundedToPaise(_ value: Double) -> Double { ... }
}

// View now reads:
private var balanceDue: Double { Money.roundedToPaise(order.total - receivedTotal) }
```

The extracted helper is testable AND reusable from any future caller.

### 6. Run the tests locally before committing

```bash
xcodebuild ... test 2>&1 | grep "Test Suite\|TEST"
```

Look for `** TEST SUCCEEDED **`. CI will also run them on PR.

---

## Test data hygiene

- **Never use real customer data** in test fixtures (use names like "Priya Mehta" — common name, no real person)
- **Never use real phone numbers** — use `9876543210` (Indian valid-pattern non-routable)
- **Never use real GSTINs** — use `07AABCS1234A1Z5` (the example from GSTN spec docs)
- **Never use real Gemini API keys, even fake-prefixed ones**

---

## When a test fails

1. **Reproduce locally first** — `xcodebuild ... test` should fail identically
2. **Read the failure message carefully** — XCTAssertEqual prints both expected and actual
3. **If the test is wrong**: fix the test. Add a comment explaining why the old expectation was wrong.
4. **If the code is wrong**: fix the code. Keep the test that caught it.
5. **If the test caught a real bug**: thank past-you. Add a CHANGELOG note.

---

## Performance baseline

As of 2026-05-28:
- **118 test cases** across 14 suites
- **~2 seconds** wall time on local M-series Mac
- **~10 minutes** end-to-end on CI (includes cold simulator boot)

If the suite slows below 30 seconds locally, profile it. Pure-logic tests should never take that long.
