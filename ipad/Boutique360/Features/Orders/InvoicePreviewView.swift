import SwiftUI
import PDFKit

/// Renders the generated invoice PDF in a PDFView wrapped for SwiftUI.
/// Includes a share/save toolbar so the boutique can email or print directly.
struct InvoicePreviewView: View {
    let pdfData: Data
    let invoiceNumber: String

    @Environment(\.dismiss) private var dismiss
    @State private var tempFileURL: URL?
    @State private var shareError: String?

    var body: some View {
        NavigationStack {
            PDFViewer(data: pdfData)
                .navigationTitle("Invoice \(invoiceNumber)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) {
                        if let url = tempFileURL {
                            ShareLink(item: url) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        } else {
                            Button {
                                tempFileURL = writeToTempFile()
                            } label: {
                                Label("Prepare share", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
                .onAppear { tempFileURL = writeToTempFile() }
        }
    }

    private func writeToTempFile() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("invoice-\(invoiceNumber).pdf")
        do {
            try pdfData.write(to: url)
            shareError = nil
            return url
        } catch {
            // L4 fix: surface the failure (e.g. disk full) instead of silently disabling Share.
            Task { @MainActor in
                ErrorBus.shared.report("Couldn't prepare invoice for sharing: \(error.localizedDescription)")
            }
            return nil
        }
    }
}

private struct PDFViewer: UIViewRepresentable {
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
