import XCTest

/// Testing §8 (Security Tests) — "Authorization escalation attempts tested."
///
/// The gap this closes, stated plainly in the adherence register: `RolePolicy`
/// is proven correct by `RolePolicyTests`, but **nothing proved it was
/// actually consulted**. Delete a gate from a view and the whole suite stayed
/// green while an assistant started seeing payments.
///
/// This is a source-level test, not a UI test. That is a deliberate trade:
/// a real XCUITest would prove more but needs a booted simulator, a signed-in
/// session and seeded data — none of which this suite has. Reading the source
/// is a weaker proof that runs in milliseconds and fails on the exact edit
/// that would cause the regression.
///
/// **What it does NOT prove:** that the gate wraps the *right* subtree, or
/// that a gated view isn't reachable by another route. It proves the call
/// exists in the file that renders the money.
final class RoleGateWiringTests: XCTestCase {

    /// Walk up from this file to the repo root, then into the app sources.
    private var featuresDir: URL {
        URL(fileURLWithPath: #filePath)            // …/Boutique360Tests/RoleGateWiringTests.swift
            .deletingLastPathComponent()           // …/Boutique360Tests
            .deletingLastPathComponent()           // …/ipad
            .appendingPathComponent("Boutique360/Features")
    }

    private func source(_ relativePath: String) throws -> String {
        let url = featuresDir.appendingPathComponent(relativePath)
        return try XCTUnwrap(try? String(contentsOf: url, encoding: .utf8),
                             "Couldn't read \(relativePath). If this file moved, update this test — don't delete it.")
    }

    /// Every file that renders a money or configuration surface, and the
    /// surface it must consult. Derived from the surface audit in commit
    /// 9eb3223.
    private static let gatedFiles: [(path: String, surface: String)] = [
        ("Orders/PaymentsSectionView.swift",        ".payments"),
        ("Orders/OrdersListView.swift",             ".payments"),
        ("Orders/OrderDetailView.swift",            ".invoice"),
        ("Orders/LockSheet.swift",                  ".lockPricing"),
        ("Orders/LockSummarySheet.swift",           ".lockPricing"),
        ("Dashboard/DashboardView.swift",           ".revenueTile"),
        ("Dashboard/DashboardView.swift",           ".paymentReminders"),
        ("Dashboard/MorningBoardView.swift",        ".moneyDueTile"),
        ("Dashboard/MorningBoardView.swift",        ".paymentReminders"),
        ("Customers/CustomerSpendSummaryView.swift", ".spendPanel"),
        ("Customers/CustomerDetailView.swift",      ".spendPanel"),
        ("Settings/SettingsView.swift",             ".gstExport"),
        ("Settings/SettingsView.swift",             ".settingsSensitive"),
    ]

    func testEveryMoneySurfaceStillConsultsRolePolicy() throws {
        var missing: [String] = []
        for entry in Self.gatedFiles {
            let src = try source(entry.path)
            if !src.contains("RolePolicy.canSee(\(entry.surface)") {
                missing.append("\(entry.path) no longer gates \(entry.surface)")
            }
        }
        XCTAssertTrue(missing.isEmpty, """
            A role gate was removed. An assistant can now see a money surface:
            \(missing.joined(separator: "\n"))
            If the gate moved somewhere legitimate, update this test's table —
            deleting the row is how the regression ships.
            """)
    }

    /// The count is pinned so that adding a `Surface` case without gating it
    /// anywhere fails here as well as in `RolePolicyTests`.
    func testEveryDeclaredSurfaceIsGatedSomewhere() throws {
        let policySrc = try XCTUnwrap(try? String(
            contentsOf: featuresDir
                .deletingLastPathComponent()
                .appendingPathComponent("Utilities/RolePolicy.swift"),
            encoding: .utf8))

        // Extract the declared cases from the Surface enum.
        //
        // `case` must be the FIRST token on a non-comment line. An earlier
        // version matched any line containing "case " and "//", which happily
        // parsed the doc comment "Adding a case here …" into a surface called
        // `.Every`.
        let declared = policySrc
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") && $0.hasPrefix("case ") }
            .compactMap { line -> String? in
                guard let name = line.dropFirst("case ".count)
                    .split(separator: " ").first else { return nil }
                return "." + name.trimmingCharacters(in: CharacterSet(charactersIn: ","))
            }

        XCTAssertFalse(declared.isEmpty, "Couldn't parse Surface cases — update this test.")

        let gatedSurfaces = Set(Self.gatedFiles.map(\.surface))
        let ungated = declared.filter { !gatedSurfaces.contains($0) }

        // .razorpayLink lives inside the already-gated PaymentsSectionView, so
        // it has no separate call site by design.
        XCTAssertEqual(ungated, [".razorpayLink"], """
            A Surface is declared but gated nowhere: \(ungated).
            Either gate it in a view, or record here why it doesn't need one.
            """)
    }
}
