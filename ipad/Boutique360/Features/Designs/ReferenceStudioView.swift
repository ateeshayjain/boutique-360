import SwiftUI

/// Start a design from a reference photo (Pinterest/Instagram/camera roll)
/// re-imagined in a chosen fabric, then flow into the existing render → VTO
/// pipeline. Operates on an existing Design row (caller guarantees one exists).
struct ReferenceStudioView: View {
    let design: Design
    let onRendered: (DesignRender) -> Void

    @EnvironmentObject private var ctx: BoutiqueContext
    @Environment(\.dismiss) private var dismiss

    @State private var referenceImage: UIImage?
    @State private var fabricImages: [UIImage] = []
    @State private var fabricDescription = ""
    @State private var phase: Phase = .idle
    @State private var resultImage: UIImage?

    enum Phase: Equatable { case idle, calling, uploading, done, failed(String) }

    var body: some View {
        Form {
            Section("Reference dress") {
                if let img = referenceImage {
                    Image(uiImage: img)
                        .resizable().scaledToFit().frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card))
                }
                ImageInputPicker { referenceImage = $0 }
                Text("Add the dress photo the customer liked — camera, library, or paste a link.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section("Fabric") {
                ForEach(Array(fabricImages.enumerated()), id: \.offset) { _, img in
                    Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 100)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.chip))
                }
                ImageInputPicker(allowedSources: [.camera, .library]) { fabricImages.append($0) }
                TextField("Or describe it (e.g. emerald Banarasi silk, gold zari)",
                          text: $fabricDescription, axis: .vertical)
                    .lineLimit(1...3)
            }

            Section {
                Button {
                    Task { await generate() }
                } label: {
                    HStack {
                        Label(buttonLabel, systemImage: "sparkles")
                        Spacer()
                        if isRunning { ProgressView() }
                    }
                }
                .disabled(isRunning || referenceImage == nil || !Config.aiEnabled)

                if referenceImage == nil {
                    Text("Add a reference dress to start.").font(.caption).foregroundStyle(.secondary)
                }
                if !Config.aiEnabled {
                    Label("Add GEMINI_API_KEY to enable AI render.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                if case .failed(let msg) = phase {
                    Text(msg).font(.caption).foregroundStyle(.red)
                }
            }

            if let img = resultImage {
                Section("Rendered") {
                    Image(uiImage: img)
                        .resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card))
                    ShareLink(item: Image(uiImage: img),
                              preview: SharePreview("\(design.name) — AI preview", image: Image(uiImage: img))) {
                        Label("Share with customer", systemImage: "square.and.arrow.up")
                    }
                    Text("Open the design's Virtual Try-On to put this on a customer.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Start from a photo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
    }

    private var isRunning: Bool { switch phase { case .calling, .uploading: true; default: false } }
    private var buttonLabel: String {
        switch phase {
        case .calling: "Asking Gemini (≈30s)…"
        case .uploading: "Saving…"
        default: resultImage == nil ? "Generate render" : "Regenerate"
        }
    }

    @MainActor
    private func generate() async {
        guard let bid = ctx.boutiqueId, let ref = referenceImage else { return }
        do {
            // Persist the reference (bucket, path) — best-effort, non-fatal for the render.
            if let jpeg = ref.jpegData(compressionQuality: 0.85) {
                let refPath = StorageService.referencePath(designId: design.id)
                _ = try? await StorageService.upload(jpeg, to: .designReferences,
                                                     path: refPath, contentType: "image/jpeg")
                try? await DesignsService.saveReferenceImagePath(designId: design.id, path: refPath)
            }

            phase = .calling
            let result = try await GeminiService.renderGarmentFromReference(
                reference: ref,
                fabricImages: fabricImages,
                fabricDescription: fabricDescription.isEmpty ? nil : fabricDescription,
                garmentType: design.garmentType,
                occasion: design.occasion,
                styleNotes: design.notesMd
            )

            phase = .uploading
            guard let png = result.pngData() else { phase = .failed("Couldn't encode result"); return }
            let renderId = UUID()
            let path = StorageService.renderPath(renderId: renderId)
            let upload = try await StorageService.upload(png, to: .designRenders,
                                                         path: path, contentType: "image/png")
            let record = try await DesignRendersService.record(NewDesignRender(
                boutique_id: bid,
                design_id: design.id,
                prompt_used: "reference-photo",
                result_image_url: nil,
                result_image_path: upload.path,
                model_used: "gemini-2.5-flash-image",
                processing_ms: 0,
                cost_estimate_usd: 0.04,
                status: RenderStatus.done.rawValue,
                error_msg: nil
            ))

            resultImage = result
            phase = .done
            onRendered(record)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
