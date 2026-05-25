import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var auth: AuthService
    @State private var email: String = ""
    @State private var sent: Bool = false
    @FocusState private var emailFocused: Bool

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "scissors")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Color.accentColor)
                Text("Boutique 360")
                    .font(.system(size: 36, weight: .semibold, design: .serif))
                Text("Designer workspace")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if sent {
                VStack(spacing: 16) {
                    Image(systemName: "envelope.badge.fill")
                        .font(.largeTitle)
                        .foregroundStyle(Color.accentColor)
                    Text("Check your email")
                        .font(.title2.weight(.medium))
                    Text("We sent a sign-in link to \(email).\nTap it on this iPad to continue.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Use a different email") {
                        sent = false
                        email = ""
                    }
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

                    Button {
                        Task {
                            let ok = await auth.signInWithMagicLink(email: email)
                            if ok { sent = true }
                        }
                    } label: {
                        if auth.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Send magic link").fontWeight(.semibold)
                        }
                    }
                    .disabled(auth.isLoading || !isValidEmail(email))
                    .frame(maxWidth: 420, minHeight: 50)
                    .background(isValidEmail(email) ? Color.accentColor : Color.gray.opacity(0.3))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

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

            // DEV: one-tap demo sign-in (remove before production)
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

            Text("Plan 3 · CRM Core")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .onAppear {
            emailFocused = true
            // DEV: launch with -auto-demo to auto-sign-in to demo user
            if CommandLine.arguments.contains("-auto-demo") {
                Task {
                    _ = await auth.signInWithPassword(
                        email: "demo@boutique360.test",
                        password: "demo-password-123"
                    )
                }
            }
        }
    }

    private func isValidEmail(_ s: String) -> Bool {
        s.contains("@") && s.contains(".")
    }
}

#Preview {
    SignInView().environmentObject(AuthService())
}
