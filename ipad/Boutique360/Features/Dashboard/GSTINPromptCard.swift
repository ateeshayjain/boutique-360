import SwiftUI

/// One-time nudge to add the boutique's GSTIN, shown on the Dashboard.
///
/// Why this exists: the app treats a non-empty GSTIN as "invoicing enabled".
/// A placeholder seeded by migration 0023 sat in production for two months and
/// was printed on GST invoices — statutory documents — as if it were real.
/// That value is now cleared, so invoicing is correctly disabled until a real
/// GSTIN is entered. This card is the "make it easy" half of that: without it,
/// the owner would only discover the problem when an invoice button is greyed
/// out mid-consultation.
///
/// Rules it follows:
/// - **Asks once.** Dismissed (or saved) → never shown again on this device.
///   Nagging every launch trains people to ignore banners.
/// - **Owner only.** Boutique tax identity is `.settingsSensitive`.
/// - **Saves inline.** No "go to Settings and find the right screen" detour.
/// - Silent when a GSTIN already exists.
struct GSTINPromptCard: View {
    @EnvironmentObject private var ctx: BoutiqueContext
    @EnvironmentObject private var roles: StaffRoleContext

    /// Per-device: this is a nudge, not a workflow gate worth a schema column.
    @AppStorage("b360.gstinPrompt.dismissed") private var dismissed = false

    @State private var gstin = ""
    @State private var saving = false
    @State private var error: String?

    private var shouldShow: Bool {
        !dismissed
            && ctx.boutique != nil
            && (ctx.boutique?.gstin ?? "").isEmpty
            && RolePolicy.canSee(.settingsSensitive, role: roles.role)
    }

    /// Empty is "not yet typed", not an error — the field shouldn't shout at
    /// someone who has typed nothing.
    private var validationProblem: String? {
        gstin.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil
            : GSTINValidator.problem(in: gstin)
    }

    @ViewBuilder
    var body: some View {
        if shouldShow { card }
    }

    private var card: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: Spacing.small) {
                HStack {
                    Label("Add your GSTIN", systemImage: "doc.text.magnifyingglass")
                        .font(.headline)
                    Spacer()
                    Button {
                        dismissed = true
                    } label: {
                        Image(systemName: "xmark")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Dismiss — don't ask again")
                }

                // States the consequence rather than just asking.
                Text("GST invoices are turned off until this is set. We won't put a placeholder on a tax document.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Spacing.small) {
                    TextField("15-character GSTIN", text: $gstin)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .frame(minHeight: 44)

                    Button {
                        Task { await save() }
                    } label: {
                        Text(saving ? "Saving…" : "Save")
                            .frame(minWidth: 72, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(saving
                              || gstin.trimmingCharacters(in: .whitespaces).isEmpty
                              || validationProblem != nil)
                }

                if let problem = validationProblem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("You can also set this any time in Settings → Boutique.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.vertical, Spacing.micro)
        }
        .accessibilityElement(children: .contain)
    }

    private func save() async {
        guard let boutique = ctx.boutique else { return }
        saving = true
        error = nil
        defer { saving = false }

        let cleaned = gstin.trimmingCharacters(in: .whitespaces).uppercased()
        do {
            try await BoutiqueService.update(id: boutique.id, patch: .init(
                name: boutique.name,
                gstin: cleaned,
                place_of_supply: boutique.placeOfSupply,
                address: boutique.address
            ))
            await ctx.refresh()
            // Saved is also "asked once" — don't reappear if the refresh lags.
            dismissed = true
        } catch {
            // Surfaced here rather than swallowed; the owner needs to know the
            // GSTIN did NOT save, or they'll assume invoicing is on.
            self.error = "Couldn't save — \(error.localizedDescription)"
        }
    }
}
