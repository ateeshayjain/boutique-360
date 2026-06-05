import SwiftUI

/// Trigger + display Gemini sketch→garment render. Shows progress, surfaces
/// errors clearly, records every attempt to design_renders (success or failure).
struct RenderView: View {
    let design: Design
    let onRendered: (DesignRender) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ctx: BoutiqueContext

    @State private var phase: Phase = .idle
    @State private var renders: [DesignRender] = []
    @State private var selectedRender: DesignRender?
    @State private var currentImage: UIImage?

    enum Phase: Equatable {
        case idle, fetchingSketch, calling, uploading, done, failed(String)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Design", value: design.name)
                if let g = design.garmentType { LabeledContent("Garment", value: g) }
                if let o = design.occasion { LabeledContent("Occasion", value: o) }
            }

            if !Config.aiEnabled {
                Section {
                    Label("Add GEMINI_API_KEY to Env.xcconfig and rebuild to enable AI renders.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }

            Section("Generate") {
                Button {
                    Task { await runRender() }
                } label: {
                    HStack {
                        Label(buttonLabel, systemImage: "sparkles")
                        Spacer()
                        if isRunning { ProgressView() }
                    }
                }
                .disabled(isRunning || !Config.aiEnabled || design.sketchImageUrl == nil)

                if design.sketchImageUrl == nil {
                    Text("Sketch first — open the canvas, draw, save. Then come back.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if case .failed(let msg) = phase {
                    Text(msg).font(.caption).foregroundStyle(.red)
                }
            }

            if let img = currentImage {
                Section("Latest render") {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    ShareLink(
                        item: Image(uiImage: img),
                        preview: SharePreview(
                            "\(design.name) — AI preview",
                            image: Image(uiImage: img)
                        )
                    ) {
                        Label("Share with customer (WhatsApp, Messages…)", systemImage: "square.and.arrow.up")
                    }
                }
            }

            if !renders.isEmpty {
                Section("History") {
                    ForEach(renders) { r in
                        HStack {
                            Image(systemName: r.isFavorite ? "star.fill" : "circle")
                                .foregroundStyle(r.isFavorite ? .yellow : .secondary)
                            VStack(alignment: .leading) {
                                Text(r.status.rawValue.capitalized).font(.subheadline)
                                Text(r.createdAt.formatted(.dateTime.day().month().hour().minute()))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let ms = r.processingMs {
                                Text("\(ms / 1000)s").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("AI render")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
        }
        .task { renders = (try? await DesignRendersService.listForDesign(design.id)) ?? [] }
    }

    private var isRunning: Bool {
        switch phase {
        case .fetchingSketch, .calling, .uploading: true
        default: false
        }
    }
    private var buttonLabel: String {
        switch phase {
        case .idle, .done, .failed: "Generate render"
        case .fetchingSketch: "Loading sketch…"
        case .calling: "Asking Gemini (≈30s)…"
        case .uploading: "Saving result…"
        }
    }

    @MainActor
    private func runRender() async {
        guard let bid = ctx.boutiqueId else { return }
        // Prefer the canonical path (stable). Fall back to the cached URL for old rows.
        let sketchPath = design.sketchImagePath ?? StorageService.sketchPath(designId: design.id)

        phase = .fetchingSketch
        let started = Date()
        do {
            let sketchUrl = try await StorageService.signedURL(bucket: .designSketches, path: sketchPath)
            let (sketchData, _) = try await URLSession.shared.data(from: sketchUrl)
            guard let sketchImg = UIImage(data: sketchData) else {
                phase = .failed("Couldn't load sketch image")
                return
            }

            phase = .calling
            let prompt = PromptTemplates.renderGarment(
                garmentType: design.garmentType, occasion: design.occasion,
                fabricNames: [], colorPalette: [], styleNotes: design.notesMd
            )
            let result = try await GeminiService.renderGarmentFromSketch(
                sketch: sketchImg,
                fabricReferences: [],
                garmentType: design.garmentType,
                occasion: design.occasion,
                fabricNames: [],
                colorPalette: [],
                styleNotes: design.notesMd
            )

            phase = .uploading
            guard let resultData = result.pngData() else {
                phase = .failed("Couldn't encode AI result")
                return
            }
            let renderId = UUID()
            let path = StorageService.renderPath(renderId: renderId)
            let upload = try await StorageService.upload(resultData, to: .designRenders, path: path, contentType: "image/png")

            let processingMs = Int(Date().timeIntervalSince(started) * 1000)
            // B3 fix: don't persist the 1-hr signed URL — only the path. Readers
            // (DesignDetailView, VTO chooser) regenerate signed URLs on demand.
            let record = try await DesignRendersService.record(NewDesignRender(
                boutique_id: bid,
                design_id: design.id,
                prompt_used: prompt,
                result_image_url: nil,
                result_image_path: upload.path,
                model_used: "gemini-2.5-flash-image",
                processing_ms: processingMs,
                cost_estimate_usd: 0.04,
                status: RenderStatus.done.rawValue,
                error_msg: nil
            ))

            currentImage = result
            renders = (try? await DesignRendersService.listForDesign(design.id)) ?? []
            phase = .done
            onRendered(record)
        } catch {
            phase = .failed(error.localizedDescription)
            // Record the failure too so user has audit trail
            if let bid = ctx.boutiqueId {
                _ = try? await DesignRendersService.record(NewDesignRender(
                    boutique_id: bid, design_id: design.id,
                    prompt_used: "", result_image_url: nil, result_image_path: nil,
                    model_used: "gemini-2.5-flash-image", processing_ms: 0, cost_estimate_usd: 0,
                    status: RenderStatus.failed.rawValue, error_msg: error.localizedDescription
                ))
            }
        }
    }
}
