import SwiftUI
import PDFKit

/// PDFKit viewer + ShareLink wrapper for an in-memory Job Card PDF.
/// R4d: when a `jobCard` is supplied, also shows the karigar phone-link
/// panel (share / regenerate) and live progress events.
struct JobCardPreviewView: View {
    let pdfData: Data
    let jobNumber: String
    var jobCard: JobCard? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ctx: BoutiqueContext
    @State private var tempURL: URL?
    @State private var shareToken: UUID?
    @State private var events: [JobCardEvent] = []
    @State private var eventsError: String?
    @State private var confirmRegenerate = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PDFKitView(data: pdfData)
                if jobCard != nil { karigarSection }
            }
            .navigationTitle("Job Card \(jobNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    if let url = tempURL {
                        ShareLink(item: url, preview: SharePreview("Job Card \(jobNumber)")) {
                            Label("Share PDF", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .onAppear { tempURL = writeTemp() }
            .task { await loadKarigarState() }
            .confirmationDialog(
                "Regenerate karigar link?",
                isPresented: $confirmRegenerate,
                titleVisibility: .visible
            ) {
                Button("Regenerate", role: .destructive) {
                    Task { await regenerate() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Old shared links will stop working. Share the new link after regenerating.")
            }
        }
    }

    // MARK: - R4d karigar link panel

    private var karigarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Karigar phone link", systemImage: "iphone.badge.play")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let token = shareToken {
                    // Deliberate deviation from the spec's wa.me wording: the
                    // karigar's phone # isn't modeled, so the share sheet lets
                    // the owner pick the WhatsApp chat — same one-tap outcome.
                    ShareLink(item: JobCardEventsService.shareURL(token: token)) {
                        Label("Share link", systemImage: "link")
                    }
                    .buttonStyle(.bordered)
                    Button(role: .destructive) {
                        confirmRegenerate = true
                    } label: {
                        Label("Regenerate", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                }
            }
            Text("Karigar opens the link on any phone — sees the design, naap, and brief; taps Shuru kiya / Silai poori / Taiyaar hai. A Taiyaar update counts as production done for deadline slack.")
                .font(.caption2).foregroundStyle(.secondary)

            if let err = eventsError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
                Button("Retry") { Task { await loadKarigarState() } }
                    .buttonStyle(.bordered)
            } else if !events.isEmpty {
                Text("Updates from karigar").font(.caption.weight(.medium))
                ForEach(events.prefix(5)) { e in
                    HStack(spacing: 8) {
                        Image(systemName: icon(for: e.event))
                            .foregroundStyle(e.event == .ready ? .green : .secondary)
                        Text(label(for: e.event))
                        Spacer()
                        Text(e.createdAt.formatted(.relative(presentation: .named)))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
    }

    private func label(for kind: JobCardEvent.Kind) -> String {
        switch kind {
        case .started:       "Shuru kiya"
        case .stitchingDone: "Silai poori"
        case .ready:         "Taiyaar hai"
        }
    }
    private func icon(for kind: JobCardEvent.Kind) -> String {
        switch kind {
        case .started:       "figure.walk"
        case .stitchingDone: "scissors"
        case .ready:         "checkmark.seal.fill"
        }
    }

    private func loadKarigarState() async {
        guard let card = jobCard, let bid = ctx.boutiqueId else { return }
        // Stale cached cards (pre-0028) may lack the token — re-fetch.
        if let token = card.shareToken {
            shareToken = token
        } else {
            shareToken = (try? await JobCardsService.get(id: card.id))?.shareToken
        }
        do {
            events = try await JobCardEventsService.list(jobCardId: card.id, boutiqueId: bid)
            eventsError = nil
        } catch {
            eventsError = "Couldn't load karigar updates: \(error.localizedDescription)"
        }
    }

    private func regenerate() async {
        guard let card = jobCard else { return }
        do {
            shareToken = try await JobCardEventsService.regenerateToken(jobCardId: card.id)
        } catch {
            ErrorBus.shared.report("Couldn't regenerate link: \(error.localizedDescription)")
        }
    }

    private func writeTemp() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(jobNumber).pdf")
        try? pdfData.write(to: url)
        return url
    }
}

private struct PDFKitView: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.document = PDFDocument(data: data)
        return v
    }
    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.dataRepresentation() != data {
            uiView.document = PDFDocument(data: data)
        }
    }
}
