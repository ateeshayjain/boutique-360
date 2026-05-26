import SwiftUI

struct DesignDetailView: View {
    let design: Design
    let customerName: String?

    @State private var current: Design
    @State private var showEdit = false
    @State private var showSketch = false
    @State private var showRender = false
    @State private var showTryOn = false
    @State private var showJobCardComposer = false
    @State private var jobCardPDF: Data?
    @State private var lastJobNumber: String = ""
    @State private var showJobCardPreview = false
    @State private var customer: Customer?

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
            Section("Workflow") {
                Button {
                    showSketch = true
                } label: {
                    Label(current.sketchImageUrl == nil ? "Sketch with Pencil" : "Edit sketch", systemImage: "pencil.and.scribble")
                }

                Button {
                    showRender = true
                } label: {
                    Label("AI render", systemImage: "sparkles")
                }
                .disabled(current.sketchImageUrl == nil)

                Button {
                    showTryOn = true
                } label: {
                    Label("Customer virtual try-on", systemImage: "person.crop.rectangle.badge.plus")
                }
                .disabled(current.customerId == nil)

                if current.customerId == nil {
                    Text("Link this design to a customer first (use Edit) to enable try-on.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }

                Button {
                    showJobCardComposer = true
                } label: {
                    Label("Send to workshop (Job Card)", systemImage: "scissors.badge.ellipsis")
                }
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
        .fullScreenCover(isPresented: $showSketch) {
            NavigationStack {
                SketchCanvasView(design: current) {
                    Task {
                        if let updated = try? await DesignsService.get(id: current.id) {
                            current = updated
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showRender) {
            NavigationStack {
                RenderView(design: current) { _ in }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showTryOn) {
            NavigationStack {
                VirtualTryOnView(design: current, customer: customer)
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showJobCardComposer) {
            NavigationStack {
                JobCardComposerView(design: current) { saved in
                    Task { await composePDF(for: saved) }
                }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showJobCardPreview) {
            if let pdf = jobCardPDF {
                JobCardPreviewView(pdfData: pdf, jobNumber: lastJobNumber)
            }
        }
        .task {
            if let cid = current.customerId {
                customer = try? await CustomersService.get(id: cid)
            }
        }
    }

    /// After the Job Card row is saved, fetch sketch + render images (signed URLs),
    /// hand everything to the PDF generator, then open the preview sheet.
    private func composePDF(for jobCard: JobCard) async {
        var sketchImg: UIImage?
        var renderImg: UIImage?

        if let path = jobCard.sketchImagePath ?? current.sketchImagePath,
           let url = try? await StorageService.signedURL(bucket: .designSketches, path: path),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let img = UIImage(data: data) {
            sketchImg = img
        }
        // Latest favorite render, if any
        if let renders = try? await DesignRendersService.listForDesign(current.id),
           let r = renders.first(where: { $0.status == .done }),
           let path = r.resultImagePath,
           let url = try? await StorageService.signedURL(bucket: .designRenders, path: path),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let img = UIImage(data: data) {
            renderImg = img
        }

        let input = JobCardPDFGenerator.Input(
            jobNumber: jobCard.jobNumber,
            dueDate: jobCard.dueDate,
            boutiqueName: customerName ?? "Boutique 360",  // overridden below if context loaded
            customerName: customerName ?? "Customer",
            garmentType: jobCard.garmentType,
            occasion: jobCard.occasion,
            measurements: jobCard.measurementsJson,
            fabrics: jobCard.fabricListJson,
            embellishments: jobCard.embellishments,
            specialInstructions: jobCard.specialInstructions,
            hindiBrief: jobCard.hindiBrief,
            sketchImage: sketchImg,
            renderImage: renderImg
        )
        jobCardPDF = JobCardPDFGenerator.render(input)
        lastJobNumber = jobCard.jobNumber
        showJobCardComposer = false
        showJobCardPreview = true
    }
}
