import SwiftUI
import PDFKit

/// PDFKit viewer + ShareLink wrapper for an in-memory Job Card PDF.
struct JobCardPreviewView: View {
    let pdfData: Data
    let jobNumber: String

    @Environment(\.dismiss) private var dismiss
    @State private var tempURL: URL?

    var body: some View {
        NavigationStack {
            PDFKitView(data: pdfData)
                .navigationTitle("Job Card \(jobNumber)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) {
                        if let url = tempURL {
                            ShareLink(item: url, preview: SharePreview("Job Card \(jobNumber)")) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
                .onAppear { tempURL = writeTemp() }
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
