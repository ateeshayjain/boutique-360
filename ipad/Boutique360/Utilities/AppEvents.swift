import Foundation

/// App-wide pub/sub for events that multiple views care about. Currently:
///   - `.appDidForeground` fires when the app returns from background. Lets
///     dashboard/list views re-fetch instead of showing stale data.
///   - `.orderDidChange(id:)` fires after a successful order mutation so
///     embedded child sections refresh.
///
/// We use Notification.Name (vs Combine subjects) because SwiftUI's
/// `.onReceive(NotificationCenter.default.publisher(for:))` is the most
/// ergonomic subscriber form and survives view lifecycle changes.
extension Notification.Name {
    static let appDidForeground = Notification.Name("Boutique360.appDidForeground")
    static let orderDidChange   = Notification.Name("Boutique360.orderDidChange")
}
