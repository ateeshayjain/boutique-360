import SwiftUI

struct DesignDetailView: View {
    let design: Design
    let customerName: String?

    @State private var current: Design
    @State private var showEdit = false

    init(design: Design, customerName: String?) {
        self.design = design
        self.customerName = customerName
        _current = State(initialValue: design)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Garment", value: current.garmentType ?? "—")
                if let o = current.occasion { LabeledContent("Occasion", value: o) }
                LabeledContent("Status") {
                    Label(current.status.label, systemImage: "circle.fill")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Customer", value: customerName ?? "Library concept")
                LabeledContent("Updated", value: current.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }
            if let notes = current.notesMd, !notes.isEmpty {
                Section("Notes") { Text(notes) }
            }
            Section("Status workflow") {
                ForEach(DesignStatus.allCases) { s in
                    if s != current.status {
                        Button {
                            Task {
                                if let updated = try? await DesignsService.update(current.id, patch: .init(status: s.rawValue)) {
                                    current = updated
                                }
                            }
                        } label: {
                            Label("Mark \(s.label)", systemImage: "arrow.right.circle")
                        }
                    }
                }
            }
            Section("Sketch canvas") {
                Label("PencilKit canvas arrives in Plan 4", systemImage: "pencil.and.scribble")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Section("AI render") {
                Label("Gemini sketch→render arrives in Plan 5", systemImage: "sparkles")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) {
            NavigationStack {
                DesignFormView(mode: .edit(current)) { updated in
                    current = updated
                    showEdit = false
                }
            }
        }
    }
}
