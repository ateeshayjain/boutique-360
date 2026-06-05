import Foundation
import os

/// Centralized logging built on Apple's `os.Logger` (iOS 14+).
///
/// Why os.Logger over print():
///   - Structured: each log carries category + level + privacy specifier
///   - Persistent: survives across launches via the unified logging system
///   - Visible: Console.app + Xcode debug console show output by default
///   - Privacy-aware: `\(name, privacy: .private)` redacts in production logs
///
/// Subsystem groups all our logs under a single string so filtering is easy:
///   `log show --predicate 'subsystem == "com.boutique360.designer.ipad"'`
///
/// Categories partition by functional area so a single broken flow doesn't
/// drown the rest. Add new categories sparingly — fewer, larger categories
/// are easier to grep than many tiny ones.
enum Log {
    private static let subsystem = "com.boutique360.designer.ipad"

    /// Auth events: sign-in attempts, magic-link callbacks, session refresh,
    /// sign-out. Never log tokens — only outcomes.
    static let auth = Logger(subsystem: subsystem, category: "auth")

    /// Network calls to Supabase + Gemini. Log the operation + outcome,
    /// never the request body (which may contain customer PII).
    static let network = Logger(subsystem: subsystem, category: "network")

    /// Storage ops: upload/download/signed-URL generation. Log the bucket
    /// + path (paths are server-generated UUIDs, not PII).
    static let storage = Logger(subsystem: subsystem, category: "storage")

    /// AI cost meter + Gemini call lifecycle. Track cost-ceiling hits.
    static let ai = Logger(subsystem: subsystem, category: "ai")

    /// Local notifications: scheduling, permission requests, fire events.
    static let notifications = Logger(subsystem: subsystem, category: "notifications")

    /// Business-logic events: order status changes, payment recorded, job
    /// card issued. Future hook for analytics.
    static let business = Logger(subsystem: subsystem, category: "business")

    /// Catch-all for things that don't fit elsewhere. Keep this category small.
    static let app = Logger(subsystem: subsystem, category: "app")
}

/*
 Privacy specifier cheatsheet (use these on every interpolated value):

 // Public — value is included in logs
 Log.business.info("Order \(orderNumber, privacy: .public) → \(status, privacy: .public)")

 // Private — redacted in production, visible in DEBUG
 Log.business.info("Customer \(customerName, privacy: .private) updated")

 // Sensitive (DPDP) — always redacted
 Log.network.error("Gemini auth failed for key \(apiKey, privacy: .sensitive)")

 // Auto — Apple decides (usually .private for non-numerics)
 Log.network.info("HTTP \(statusCode)")  // status code is implicitly .public

 Level guidance:
   .debug  — verbose, useful for diagnostics, not retained long
   .info   — normal operation milestones, retained on disk
   .notice — significant events (sign-in, order placed)
   .error  — recoverable failures
   .fault  — unrecoverable, often indicates a bug
*/
