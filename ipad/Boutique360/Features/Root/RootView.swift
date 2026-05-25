import SwiftUI

/// Auth gate: shows SignInView when unauthenticated, AppShellView when authenticated.
struct RootView: View {
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        Group {
            if auth.session != nil {
                AppShellView()
            } else {
                SignInView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: auth.session != nil)
    }
}
