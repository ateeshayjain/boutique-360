import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Email", value: auth.session?.user.email ?? "—")
                LabeledContent("User ID", value: auth.session?.user.id.uuidString.prefix(8).description ?? "—")
            }
            Section("Backend") {
                LabeledContent("Supabase URL", value: Config.supabaseURL.host ?? "—")
                LabeledContent("App version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            }
            Section {
                Button(role: .destructive) {
                    Task { await auth.signOut() }
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("Settings")
    }
}
