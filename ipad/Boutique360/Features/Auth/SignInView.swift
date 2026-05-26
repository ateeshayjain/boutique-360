import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var auth: AuthService
    @State private var email: String = ""
    @State private var sent: Bool = false
    @State private var pwdSignInRequested = false
    @FocusState private var emailFocused: Bool

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "scissors")
                    .font(.system(.largeTitle, design: .serif).weight(.light))
                    .imageScale(.large)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text("Boutique 360")
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Designer workspace")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if sent {
                VStack(spacing: 16) {
                    Image(systemName: "envelope.badge.fill")
                        .font(.title)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    Text("Check your email")
                        .font(.title2.weight(.medium))
                        .accessibilityAddTraits(.isHeader)
                    Text("We sent a sign-in link to \(email).\nTap it on this iPad to continue.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Use a different email") {
                        sent = false
                        email = ""
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .padding(.top, 8)
                }
                .frame(maxWidth: 420)
            } else {
                VStack(spacing: 16) {
                    TextField("you@boutique.com", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .padding(14)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .focused($emailFocused)
                        .frame(maxWidth: 420)
                        .accessibilityLabel("Email address")

                    Button {
                        Task {
                            let ok = await auth.signInWithMagicLink(email: email)
                            if ok { sent = true }
                        }
                    } label: {
                        if auth.isLoading {
                            ProgressView()
                                .controlSize(.regular)
                                .frame(maxWidth: .infinity, minHeight: 30)
                        } else {
                            Text("Send magic link")
                                .frame(maxWidth: .infinity, minHeight: 30)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(auth.isLoading || !isValidEmail(email))
                    .frame(maxWidth: 420)

                    if let err = auth.lastError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                    }
                }
            }

            Spacer()

            #if DEBUG
            // DEV ONLY — compiled out of Release builds.
            VStack(spacing: 4) {
                Button {
                    Task {
                        _ = await auth.signInWithPassword(
                            email: "demo@boutique360.test",
                            password: "demo-password-123"
                        )
                    }
                } label: {
                    Label("Continue as demo (dev)", systemImage: "person.badge.shield.checkmark")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Text("Debug build")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            #endif
        }
        .padding(40)
        .onAppear {
            emailFocused = true
            #if DEBUG
            // DEV: launch with -auto-demo to auto-sign-in to demo user.
            // Compiled out of Release builds.
            if CommandLine.arguments.contains("-auto-demo") && !pwdSignInRequested {
                pwdSignInRequested = true
                Task {
                    _ = await auth.signInWithPassword(
                        email: "demo@boutique360.test",
                        password: "demo-password-123"
                    )
                }
            }
            #endif
        }
    }

    /// Stricter than `contains("@") && contains(".")` — uses NSDataDetector
    /// which Apple uses internally for link detection.
    private func isValidEmail(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 5, trimmed.contains("@") else { return false }
        let parts = trimmed.split(separator: "@", maxSplits: 1)
        guard parts.count == 2,
              let domain = parts.last, domain.contains("."),
              !parts.first!.isEmpty, !domain.hasPrefix("."), !domain.hasSuffix(".")
        else { return false }
        return true
    }
}

#Preview {
    SignInView().environmentObject(AuthService())
}
