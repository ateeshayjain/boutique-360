import SwiftUI

/// Rich style profile editor — HIG-aligned Form with semantic Sections.
/// Lives as a separate sheet so the 360° detail view stays scannable.
struct CustomerStyleProfileView: View {
    let customer: Customer
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ctx: BoutiqueContext

    @State private var loaded = false
    @State private var saving = false
    @State private var error: String?

    @State private var persona: StylePersona?
    @State private var bodyType: BodyType?
    @State private var skinTone: SkinTone?
    @State private var budget: BudgetBand?
    @State private var heightCm: Int = 160
    @State private var colorPaletteRaw: String = ""
    @State private var fabricPrefRaw: String = ""
    @State private var avoidFabricRaw: String = ""
    @State private var designersRaw: String = ""
    @State private var pinterest: String = ""
    @State private var instagram: String = ""
    @State private var notes: String = ""

    var body: some View {
        Form {
            Section("Style persona") {
                Picker("Persona", selection: $persona) {
                    Text("Not set").tag(StylePersona?.none)
                    ForEach(StylePersona.allCases) {
                        Label($0.label, systemImage: $0.systemImage).tag(StylePersona?.some($0))
                    }
                }
            }

            Section("Body") {
                Picker("Body type", selection: $bodyType) {
                    Text("Not set").tag(BodyType?.none)
                    ForEach(BodyType.allCases) { Text($0.label).tag(BodyType?.some($0)) }
                }
                Stepper(value: $heightCm, in: 120...210) {
                    LabeledContent("Height", value: "\(heightCm) cm")
                }
                Picker("Skin tone", selection: $skinTone) {
                    Text("Not set").tag(SkinTone?.none)
                    ForEach(SkinTone.allCases) { Text($0.label).tag(SkinTone?.some($0)) }
                }
                Picker("Budget band", selection: $budget) {
                    Text("Not set").tag(BudgetBand?.none)
                    ForEach(BudgetBand.allCases) { Text($0.label).tag(BudgetBand?.some($0)) }
                }
            }

            Section {
                TextField("Loves wearing (comma separated)", text: $colorPaletteRaw)
                    .autocorrectionDisabled()
            } header: { Text("Color palette") }
              footer: { Text("e.g. jewel tones, pastels, earthy").font(.caption2) }

            Section("Fabrics") {
                TextField("Prefers (comma separated)", text: $fabricPrefRaw).autocorrectionDisabled()
                TextField("Avoids (allergies, dislikes)", text: $avoidFabricRaw).autocorrectionDisabled()
            }

            Section("Inspiration") {
                TextField("Favorite designers", text: $designersRaw).autocorrectionDisabled()
                TextField("Pinterest URL", text: $pinterest)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Instagram handle (without @)", text: $instagram)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }

            Section("Style notes") {
                TextEditor(text: $notes).frame(minHeight: 100)
            }

            if let err = error {
                Section { Text(err).foregroundStyle(.red).font(.caption) }
            }
        }
        .navigationTitle("Style profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(saving ? "Saving…" : "Save") { Task { await save() } }
                    .disabled(saving || ctx.boutiqueId == nil)
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard !loaded else { return }
        defer { loaded = true }
        if let p = try? await CustomerProfilesService.get(customerId: customer.id) {
            persona = p.stylePersona.flatMap(StylePersona.init(rawValue:))
            bodyType = p.bodyType.flatMap(BodyType.init(rawValue:))
            skinTone = p.skinTone.flatMap(SkinTone.init(rawValue:))
            budget = p.budgetBand.flatMap(BudgetBand.init(rawValue:))
            heightCm = p.heightCm ?? 160
            colorPaletteRaw = p.colorPalette.joined(separator: ", ")
            fabricPrefRaw = p.fabricPreferences.joined(separator: ", ")
            avoidFabricRaw = p.avoidFabrics.joined(separator: ", ")
            designersRaw = p.favoriteDesigners.joined(separator: ", ")
            pinterest = p.pinterestUrl ?? ""
            instagram = p.instagramHandle ?? ""
            notes = p.styleNotesMd ?? ""
        }
    }

    private func splitCSV(_ s: String) -> [String] {
        s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func save() async {
        guard let bid = ctx.boutiqueId else { return }
        saving = true; defer { saving = false }
        do {
            let profile = CustomerProfile(
                customerId: customer.id,
                boutiqueId: bid,
                stylePersona: persona?.rawValue,
                colorPalette: splitCSV(colorPaletteRaw),
                fabricPreferences: splitCSV(fabricPrefRaw),
                avoidFabrics: splitCSV(avoidFabricRaw),
                bodyType: bodyType?.rawValue,
                heightCm: heightCm,
                skinTone: skinTone?.rawValue,
                budgetBand: budget?.rawValue,
                favoriteDesigners: splitCSV(designersRaw),
                pinterestUrl: pinterest.isEmpty ? nil : pinterest,
                instagramHandle: instagram.isEmpty ? nil : instagram,
                styleNotesMd: notes.isEmpty ? nil : notes
            )
            _ = try await CustomerProfilesService.upsert(profile)
            onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
