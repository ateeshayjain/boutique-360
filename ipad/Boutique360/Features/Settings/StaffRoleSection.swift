import SwiftUI

/// R4b — hand the iPad to an assistant, and take it back.
///
/// Three states, because the affordances genuinely differ:
/// no PIN → there is nothing to hand over *to*; owner → hand over / change;
/// assistant → the only way forward is proving you're the owner.
struct StaffRoleSection: View {
    @EnvironmentObject private var roles: StaffRoleContext
    @State private var sheet: PinEntrySheet.Mode?

    var body: some View {
        Section {
            LabeledContent("Mode", value: roles.role == .owner ? "Owner" : "Assistant")

            if !roles.hasPin {
                Button {
                    sheet = .set
                } label: {
                    Label("Set assistant PIN", systemImage: "lock")
                        .frame(minHeight: 44)
                }
            } else if roles.role == .owner {
                Button {
                    sheet = .change
                } label: {
                    Label("Change PIN", systemImage: "lock.rotation")
                        .frame(minHeight: 44)
                }
                Button {
                    // Reducing privilege needs no proof — the owner is the
                    // one tapping, and asking for the PIN here would only
                    // train them to type it in front of the assistant.
                    roles.handOverToAssistant()
                } label: {
                    Label("Hand over to assistant", systemImage: "person.badge.shield.checkmark")
                        .frame(minHeight: 44)
                }
            } else {
                Button {
                    sheet = .unlock
                } label: {
                    Label("Unlock as owner", systemImage: "lock.open")
                        .frame(minHeight: 44)
                }
            }
        } header: {
            Text("Who's using this iPad")
        } footer: {
            Text(footerCopy)
        }
        .sheet(item: $sheet) { mode in
            PinEntrySheet(mode: mode).environmentObject(roles)
        }
    }

    /// Says what the gate actually does. Overstating it would be worse than
    /// saying nothing: this hides money on screen, it does not stop anyone
    /// who has the account password.
    private var footerCopy: String {
        if !roles.hasPin {
            return "Set a PIN so you can hand the iPad to an assistant with payments, invoices and revenue hidden."
        }
        return roles.role == .owner
            ? "Assistant mode hides payments, invoices, revenue and settings on this screen. It doesn't restrict the account itself."
            : "Payments, invoices and revenue are hidden until an owner unlocks."
    }
}

extension PinEntrySheet.Mode: Identifiable {
    public var id: Int {
        switch self {
        case .set: 0
        case .change: 1
        case .unlock: 2
        }
    }
}
