import SwiftUI

/// Auth gate: shows SignInView when unauthenticated, AppShellView when authenticated.
struct RootView: View {
    @EnvironmentObject private var auth: AuthService
    @Environment(\.scenePhase) private var scenePhase
    // HIG audit fix: respect Reduce Motion on the auth transition too.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if auth.session != nil {
                AppShellView()
            } else {
                SignInView()
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: AnimationToken.standard),
                   value: auth.session != nil)
        // H4 fix: broadcast when the app returns from background so dashboards
        // and lists re-fetch instead of trusting hours-old state.
        .onChange(of: scenePhase) { _, new in
            if new == .active {
                NotificationCenter.default.post(name: .appDidForeground, object: nil)
            }
        }
        // Central error toast for non-blocking failures (status updates, etc.)
        .errorToastOverlay()
    }
}
