import SwiftUI

/// R4b — set / change / unlock the assistant PIN.
///
/// The three `PinPolicy.LockState` cases get three visibly different
/// treatments. A countdown rendered for `.capped` would be a lie — nothing
/// is counting down there, and the owner would sit and wait for a timer
/// that never expires (Content §3).
struct PinEntrySheet: View {
    enum Mode { case set, change, unlock }

    let mode: Mode
    @EnvironmentObject private var roles: StaffRoleContext
    @Environment(\.dismiss) private var dismiss

    @State private var currentPin = ""
    @State private var pin = ""
    @State private var confirmPin = ""
    @State private var message: String?
    @State private var isError = true
    @State private var now = Date()
    @State private var authInFlight = false

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var lockState: PinPolicy.LockState {
        PinPolicy.lockState(roles.attempts, now: now)
    }

    private var entryDisabled: Bool {
        mode == .unlock && lockState != .open
    }

    var body: some View {
        NavigationStack {
            Form {
                if mode == .unlock, case .cooldown(let seconds) = lockState {
                    Section {
                        Label("Too many attempts. Try again in \(seconds)s.",
                              systemImage: "clock")
                            .foregroundStyle(.orange)
                    }
                }
                if mode == .unlock, lockState == .capped {
                    Section {
                        // Deliberately no countdown here.
                        Label("Too many wrong PINs. Use this iPad's passcode to restore owner mode.",
                              systemImage: "lock.trianglebadge.exclamationmark")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    if mode == .change {
                        SecureField("Current PIN", text: $currentPin)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                    }
                    SecureField(mode == .unlock ? "PIN" : "New PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .disabled(entryDisabled)
                    if mode != .unlock {
                        SecureField("Confirm PIN", text: $confirmPin)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                    }
                } footer: {
                    if mode != .unlock {
                        Text("4 to 6 digits. Avoid runs like 1234 and repeats like 0000.")
                    }
                }

                if let message {
                    Section {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(isError ? .red : .secondary)
                    }
                }

                if mode == .unlock {
                    Section {
                        Button {
                            Task { await runDeviceAuth() }
                        } label: {
                            Label("Unlock with Face ID / device passcode",
                                  systemImage: "faceid")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .disabled(authInFlight)
                    } footer: {
                        // Shown in .open too — an owner who forgets the PIN
                        // should never be stranded.
                        Text("Uses this iPad's own passcode or Face ID.")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .unlock ? "Unlock" : "Save") { submit() }
                        .disabled(entryDisabled || pin.isEmpty)
                }
            }
            .onReceive(tick) { now = $0 }
        }
    }

    private var title: String {
        switch mode {
        case .set:    "Set assistant PIN"
        case .change: "Change PIN"
        case .unlock: "Unlock as owner"
        }
    }

    private func submit() {
        message = nil
        isError = true
        switch mode {
        case .set, .change:
            guard pin == confirmPin else { message = "The two PINs don't match."; return }
            let result = mode == .set
                ? roles.setPin(pin)
                : roles.changePin(current: currentPin, new: pin)
            switch result {
            case .ok:
                dismiss()
            case .wrongCurrent:
                message = "That's not your current PIN."
            case .storageFailed:
                message = "Couldn't save the PIN to this iPad's Keychain. Try again."
            case .invalid(let problem):
                message = copy(for: problem)
            }
        case .unlock:
            switch roles.unlockToOwner(pin: pin) {
            case .ok:
                dismiss()
            case .wrong(let remaining):
                pin = ""
                message = remaining == 1
                    ? "Wrong PIN. 1 attempt left before a short lockout."
                    : "Wrong PIN. \(remaining) attempts left before a short lockout."
            case .cooldown(let seconds):
                pin = ""
                message = "Too many attempts. Try again in \(seconds)s."
            case .capped:
                pin = ""
                message = "Too many wrong PINs. Use this iPad's passcode to restore owner mode."
            case .noPinSet:
                message = "No PIN is set on this iPad."
            case .storageFailed:
                message = "Couldn't save owner mode to this iPad's Keychain, so it wasn't switched. Try again."
            }
        }
    }

    /// Never echoes the entered PIN back — not in the message, not in a log.
    private func copy(for problem: PinPolicy.SetError) -> String {
        switch problem {
        case .tooShort, .tooLong: "PIN must be 4–6 digits."
        case .notNumeric:         "PIN must be digits only."
        case .tooSimple:          "Choose a less predictable PIN — no runs like 1234 or repeats like 0000."
        }
    }

    private func runDeviceAuth() async {
        authInFlight = true
        defer { authInFlight = false }
        switch await roles.unlockToOwnerWithDeviceAuth() {
        case .ok:
            dismiss()
        case .noPasscodeSet:
            message = "This iPad has no passcode set, so owner mode can't be restored this way. Set a device passcode in Settings."
        case .cancelledOrFailed:
            message = "Couldn't verify with Face ID or the device passcode."
        case .storageFailed:
            message = "Verified, but owner mode couldn't be saved to this iPad's Keychain. Try again."
        }
    }
}
