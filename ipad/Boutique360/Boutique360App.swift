import SwiftUI

@main
struct Boutique360App: App {
    @StateObject private var auth = AuthService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .onOpenURL { url in
                    Task { await auth.handleAuthCallback(url: url) }
                }
        }
    }
}
