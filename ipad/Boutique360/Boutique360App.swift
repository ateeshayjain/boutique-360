import SwiftUI

@main
struct Boutique360App: App {
    @StateObject private var auth = AuthService()
    @StateObject private var boutiqueCtx = BoutiqueContext.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(boutiqueCtx)
                .onOpenURL { url in
                    Task { await auth.handleAuthCallback(url: url) }
                }
                .onChange(of: auth.session?.user.id) { _, newId in
                    if newId != nil {
                        Task { await boutiqueCtx.refresh() }
                    } else {
                        boutiqueCtx.clear()
                    }
                }
        }
    }
}
