import SwiftUI

/// Composes a Job Card from a finalised design. Auto-pulls customer measurements,
/// lets the designer add fabric line items + embellishment notes, optionally
/// generates a Romanized-Hindi brief via Gemini, then saves the card and opens
/// the PDF preview for sharing/printing.
struct JobCardComposerView: View {
    let design: Design
    let onSaved: (JobCard) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ctx: BoutiqueContext

    // Customer + measurement state
    @State private var customer: Customer?
    @State private var availableMeasurements: [CustomerMeasurement] = []
    @State private var selectedMeasurement: CustomerMeasurement?

    // Form fields
    @State private var dueDate: Date = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    @State private var hasDueDate = true
    @State private var fabrics: [FabricLine] = []
    @State private var embellishments: String = ""
    @State private var specialNotes: String = ""
    @State private var karigarName: String = ""        // optional, just affects brief greeting
    @State private var hindiBrief: String = ""
    @State private var generatingBrief = false

    // Save state
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Design") {
                LabeledContent("Name", value: design.name)
                if let g = design.garmentType { LabeledContent("Garment", value: g) }
                if let o = design.occasion { LabeledContent("Occasion", value: o) }
            }

            Section("Customer measurements") {
                if availableMeasurements.isEmpty {
                    Label("No measurements found for this customer.", systemImage: "ruler")
                        .foregroundStyle(.orange).font(.callout)
                } else {
                    Picker("Use measurement set", selection: $selectedMeasurement) {
                        Text("None").tag(CustomerMeasurement?.none)
                        ForEach(availableMeasurements) { m in
                            Text("\(m.garmentType.capitalized) — \(m.takenAt.formatted(date: .abbreviated, time: .omitted))")
                                .tag(CustomerMeasurement?.some(m))
                        }
                    }
                    if let m = selectedMeasurement {
                        let pairs = m.measurementsJson.sorted { $0.key < $1.key }
                        ForEach(pairs, id: \.key) { k, v in
                            LabeledContent(k.replacingOccurrences(of: "_", with: " ").capitalized,
                                           value: String(format: "%.1f\"", v))
                        }
                    }
                }
            }

            Section("Fabric") {
                ForEach($fabrics) { $f in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Name (e.g. Banarasi silk)", text: $f.name)
                        HStack {
                            TextField("Color", text: Binding(get: { f.color ?? "" }, set: { f.color = $0.isEmpty ? nil : $0 }))
                            Stepper(value: $f.quantityMeters, in: 0.0...50.0, step: 0.5) {
                                Text("\(String(format: "%.1f", f.quantityMeters)) m").monospacedDigit()
                            }.frame(width: 200)
                        }
                        Picker("Role", selection: Binding(get: { f.role ?? "main" }, set: { f.role = $0 })) {
                            Text("Main").tag("main")
                            Text("Lining").tag("lining")
                            Text("Trim").tag("trim")
                            Text("Embellishment").tag("embellishment")
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { fabrics.remove(atOffsets: $0) }

                Button {
                    fabrics.append(FabricLine(name: "", color: nil, quantityMeters: 1.0, supplier: nil, role: "main"))
                } label: {
                    Label("Add fabric line", systemImage: "plus.circle")
                }
            }

            Section("Embellishments & special instructions") {
                TextField("e.g. Heavy zari border, gold sequin yoke",
                          text: $embellishments, axis: .vertical)
                    .lineLimit(2...4)
                TextField("e.g. Customer allergic to polyester, extra ease at waist",
                          text: $specialNotes, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section("Workshop") {
                Toggle("Due date set", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("Ready by", selection: $dueDate, in: Date()..., displayedComponents: .date)
                }
                TextField("Karigar name (optional — used in brief greeting)", text: $karigarName)
            }

            Section("AI tailor brief (Romanized Hindi)") {
                if !Config.aiEnabled {
                    Label("Add GEMINI_API_KEY to enable AI brief.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).font(.callout)
                } else {
                    Button {
                        Task { await generateBrief() }
                    } label: {
                        HStack {
                            Label(hindiBrief.isEmpty ? "Generate Hinglish brief" : "Regenerate brief",
                                  systemImage: "sparkles")
                            Spacer()
                            if generatingBrief { ProgressView() }
                        }
                    }
                    .disabled(generatingBrief)
                }

                if !hindiBrief.isEmpty {
                    TextEditor(text: $hindiBrief)
                        .frame(minHeight: 140)
                        .font(.callout)
                    Text("Edit freely — your changes will be saved verbatim in the Job Card.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            if let err = error {
                Section { Text(err).foregroundStyle(.red).font(.caption) }
            }
        }
        .navigationTitle("New Job Card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(saving ? "Saving…" : "Create & open PDF") {
                    Task { await save() }
                }
                .disabled(saving || ctx.boutiqueId == nil)
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let cid = design.customerId else { return }
        customer = try? await CustomersService.get(id: cid)
        availableMeasurements = (try? await MeasurementsService.listForCustomer(cid)) ?? []
        // Auto-select the measurement matching the design's garment type, else latest
        if let g = design.garmentType?.lowercased() {
            selectedMeasurement = availableMeasurements.first { $0.garmentType.lowercased() == g }
                                  ?? availableMeasurements.first
        } else {
            selectedMeasurement = availableMeasurements.first
        }
    }

    private func generateBrief() async {
        generatingBrief = true
        defer { generatingBrief = false }
        do {
            hindiBrief = try await GeminiService.generateTailorBrief(
                garmentType: design.garmentType,
                occasion: design.occasion,
                customerNotes: specialNotes.isEmpty ? design.notesMd : specialNotes,
                fabricList: fabrics,
                measurements: selectedMeasurement?.measurementsJson,
                embellishments: embellishments.isEmpty ? nil : embellishments,
                dueDate: hasDueDate ? formatDate(dueDate) : nil,
                karigarName: karigarName.isEmpty ? nil : karigarName
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() async {
        guard let bid = ctx.boutiqueId else { return }
        saving = true
        defer { saving = false }
        do {
            let jobNumber = try await JobCardsService.generateJobNumber(boutiqueId: bid)
            let card = NewJobCard(
                boutique_id: bid,
                job_number: jobNumber,
                design_id: design.id,
                order_id: nil,
                customer_id: design.customerId,
                garment_type: design.garmentType,
                occasion: design.occasion,
                assigned_karigar_id: nil,
                due_date: hasDueDate ? formatDate(dueDate) : nil,
                status: JobCardStatus.draft.rawValue,
                measurements_json: selectedMeasurement?.measurementsJson,
                fabric_list_json: fabrics,
                embellishments: embellishments.isEmpty ? nil : embellishments,
                special_instructions: specialNotes.isEmpty ? nil : specialNotes,
                hindi_brief: hindiBrief.isEmpty ? nil : hindiBrief,
                sketch_image_path: design.sketchImagePath,
                render_image_path: nil    // could fetch latest favorite render here
            )
            let saved = try await JobCardsService.create(card)
            onSaved(saved)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
