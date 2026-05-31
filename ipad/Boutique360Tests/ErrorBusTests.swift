import XCTest
@testable import Boutique360

/// Tests for the central error-toast pipeline (silent-failure-hunter audit fix).
/// The Toast struct is value-equatable and identifiable — these tests guard
/// that contract so SwiftUI's `.onChange(of: bus.current)` works correctly.
@MainActor
final class ErrorBusTests: XCTestCase {

    func testReportSetsCurrentToast() {
        let bus = ErrorBus.shared
        bus.current = nil

        bus.report("Test message")
        XCTAssertNotNil(bus.current)
        XCTAssertEqual(bus.current?.message, "Test message")
        XCTAssertTrue(bus.current?.isError ?? false, "Default is error toast")
    }

    func testNonErrorReportFlagsAsInfo() {
        let bus = ErrorBus.shared
        bus.current = nil

        bus.report("Hello", isError: false)
        XCTAssertEqual(bus.current?.isError, false)
    }

    func testToastsWithSameMessageHaveDifferentIDs() {
        // The Identifiable contract: each report() creates a new Toast with a
        // unique ID even if the message is the same. This is what makes SwiftUI's
        // `.animation(_, value: toast.id)` re-fire for repeat errors.
        let a = ErrorBus.Toast(message: "Same", isError: true)
        let b = ErrorBus.Toast(message: "Same", isError: true)
        XCTAssertNotEqual(a.id, b.id)
        // Equatable conformance compares everything including id, so they're !=.
        XCTAssertNotEqual(a, b)
    }

    func testToastEqualityIncludesID() {
        let toast = ErrorBus.Toast(message: "Hello", isError: false)
        XCTAssertEqual(toast, toast)
    }

    func testReportingTwiceReplacesCurrent() {
        let bus = ErrorBus.shared
        bus.report("First")
        let first = bus.current
        bus.report("Second")
        XCTAssertNotEqual(bus.current?.id, first?.id)
        XCTAssertEqual(bus.current?.message, "Second")
    }
}
