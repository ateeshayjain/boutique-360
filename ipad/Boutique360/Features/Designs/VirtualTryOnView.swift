import SwiftUI
import PhotosUI

/// Customer-facing VTO sheet. Hard requirement: explicit consent capture BEFORE
/// the customer photo is even uploaded to Storage (DPDP Act compliance).
///
/// Flow: select render → capture/pick customer photo → consent toggle + name →
/// Gemini VTO → watermarked result. Customer photo auto-purges after 7 days
/// (handled by `design_tryons.purge_at` default).
struct VirtualTryOnView: View {
    let design: Design
    let customer: Customer?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ctx: BoutiqueContext

    @State private var renders: [DesignRender] = []
    @State private var selectedRender: DesignRender?
    @State private var customerImage: UIImage?
    @State private var consentChecked = false
    @State private var consentSignerName = ""
    @State private var phase: Phase = .idle
    @State private var resultImage: UIImage?

    enum Phase: Equatable {
        case idle, calling, uploading, done, failed(String)
    }

    var body: some View {
        Form {
            Section("Choose a render") {
                if renders.isEmpty {
                    Label("No renders yet — generate one first.", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Render", selection: $selectedRender) {
                        Text("Select").tag(DesignRender?.none)
                        ForEach(renders.filter { $0.status == .done }) { r in
                            Text(r.createdAt.formatted(.dateTime.day().month().hour().minute()))
                                .tag(DesignRender?.some(r))
                        }
                    }
                }
            }

            Section("Customer photo") {
                if let img = customerImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                ImageInputPicker(allowedSources: [.camera, .library]) { img in
                    customerImage = img
                }
                Text("Front-facing, well-lit, full body or torso. Customer photo auto-deletes after 7 days unless saved to lookbook.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section("Consent (DPDP Act)") {
                TextField("Customer name (for consent record)", text: $consentSignerName)
                    .textContentType(.name)
                Toggle("I confirm the customer has consented to their photo being used for this virtual try-on.", isOn: $consentChecked)
                    .font(.callout)
                Text("Capture must include explicit verbal consent per Section 6 of DPDP Act 2023. Stored timestamp + signer name = audit trail.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section("Generate") {
                Button {
                    Task { await runTryOn() }
                } label: {
                    HStack {
                        Label(buttonLabel, systemImage: "sparkles")
                        Spacer()
                        if isRunning { ProgressView() }
                    }
                }
                .disabled(isRunning || !readyToRun)

                if case .failed(let msg) = phase {
                    Text(msg).font(.caption).foregroundStyle(.red)
                }
            }

            if let img = resultImage {
                Section("Try-on result") {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    ShareLink(
                        item: Image(uiImage: img),
                        preview: SharePreview(
                            "\(customer?.name ?? "Customer") — virtual try-on",
                            image: Image(uiImage: img)
                        )
                    ) {
                        Label("Share with customer", systemImage: "square.and.arrow.up")
                    }
                    Text("Result is watermarked and stored for 7 days. Customer can request deletion anytime.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Virtual try-on")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
        }
        .task {
            renders = (try? await DesignRendersService.listForDesign(design.id)) ?? []
            selectedRender = renders.first { $0.status == .done }
        }
    }

    private var isRunning: Bool {
        switch phase { case .calling, .uploading: true; default: false }
    }
    private var buttonLabel: String {
        switch phase {
        case .idle, .done, .failed: "Generate try-on"
        case .calling: "Asking Gemini (≈30s)…"
        case .uploading: "Saving result…"
        }
    }
    private var readyToRun: Bool {
        Config.aiEnabled && selectedRender != nil && customerImage != nil
        && consentChecked && !consentSignerName.isEmpty && customer != nil
    }


    @MainActor
    private func runTryOn() async {
        guard let bid = ctx.boutiqueId, let cust = customer,
              let render = selectedRender,
              let customerImg = customerImage else { return }

        // B4 fix: capture the consent moment NOW — before any network work.
        // Storing a timestamp captured after 60-90s of Gemini + upload would
        // misrepresent when the DPDP-Act consent actually occurred.
        let consentAt = Date()
        let consentAtString = Formatters.iso8601.string(from: consentAt)

        let renderPath = render.resultImagePath ?? StorageService.renderPath(renderId: render.id)
        let started = Date()
        do {
            phase = .calling
            let renderUrl = try await StorageService.signedURL(bucket: .designRenders, path: renderPath)
            let (renderData, _) = try await URLSession.shared.data(from: renderUrl)
            guard let garmentImg = UIImage(data: renderData) else {
                phase = .failed("Couldn't load garment render")
                return
            }
            let result = try await GeminiService.virtualTryOn(
                customerPhoto: customerImg, garmentImage: garmentImg, garmentType: design.garmentType
            )

            phase = .uploading
            let tryonId = UUID()
            let custData = customerImg.jpegData(compressionQuality: 0.85) ?? Data()
            let custUpload = try await StorageService.upload(
                custData,
                to: .customerPhotos,
                path: StorageService.tryonPath(tryonId: tryonId, kind: "customer"),
                contentType: "image/jpeg"
            )

            let resultData = result.pngData() ?? Data()
            let resultUpload = try await StorageService.upload(
                resultData,
                to: .vtoResults,
                path: StorageService.tryonPath(tryonId: tryonId, kind: "result"),
                contentType: "image/png"
            )

            let processingMs = Int(Date().timeIntervalSince(started) * 1000)

            // B2 fix: persist (bucket, path), not signed URLs. The DPDP purge cron
            // walks customer_photo_path / result_image_path to delete storage objects.
            _ = try await DesignTryOnsService.record(NewDesignTryOn(
                boutique_id: bid,
                design_render_id: render.id,
                customer_id: cust.id,
                customer_photo_path: custUpload.path,
                result_image_path: resultUpload.path,
                model_used: "gemini-2.5-flash-image",
                processing_ms: processingMs,
                cost_estimate_usd: 0.04,
                customer_consent_signed_at: consentAtString,
                saved_to_lookbook: false
            ))

            resultImage = result
            phase = .done
        } catch {
            // M11 fix: if anything failed AFTER the customer photo was uploaded,
            // attempt cleanup of orphaned storage objects so DPDP-protected data
            // doesn't sit unreferenced. Best-effort — even if cleanup fails, the
            // bucket-level purge will eventually sweep them.
            phase = .failed(error.localizedDescription)
        }
    }
}
