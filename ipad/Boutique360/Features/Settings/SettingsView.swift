import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var ctx: BoutiqueContext
    @State private var confirmSignOut = false

    var body: some View {
        Form {
            Section("Boutique") {
                LabeledContent("Name", value: ctx.boutique?.name ?? "—")
                LabeledContent("GSTIN", value: ctx.boutique?.gstin ?? "—")
                LabeledContent("Place of supply", value: ctx.boutique?.placeOfSupply ?? "—")
                if ctx.boutique?.gstin == nil {
                    Label("GSTIN missing — invoices disabled.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Section("Account") {
                LabeledContent("Email", value: auth.session?.user.email ?? "—")
                LabeledContent("Role", value: ctx.staffRole?.capitalized ?? "—")
            }
            Section("App") {
                LabeledContent("Supabase URL", value: Config.supabaseURL.host ?? "—")
                LabeledContent("App version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            }
            Section {
                Button(role: .destructive) {
                    confirmSignOut = true
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Sign out of Boutique 360?",
            isPresented: $confirmSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) {
                Task { await auth.signOut() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You'll need your email to sign back in.")
        }
    }
}
