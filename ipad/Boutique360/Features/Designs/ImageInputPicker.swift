import SwiftUI
import PhotosUI
import UIKit

enum URLInputError: Error, Equatable { case empty, notHTTP, likelyBlockedHost, malformed }

/// Pure, testable URL validation. No global state, no network — just structural checks.
enum ImageURLValidator {
    private static let blockedHosts = ["instagram.com", "pinterest.com", "pin.it"]
    static func validate(_ raw: String) -> Result<URL, URLInputError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return .failure(.malformed) }
        guard scheme == "http" || scheme == "https" else { return .failure(.notHTTP) }
        let host = (url.host ?? "").lowercased()
        if blockedHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            return .failure(.likelyBlockedHost)
        }
        return .success(url)
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController(); c.sourceType = .camera; c.delegate = context.coordinator; return c
    }
    func updateUIViewController(_ c: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

struct ImageInputPicker: View {
    enum Source { case camera, library, url }
    var allowedSources: [Source] = [.camera, .library, .url]
    let onImage: (UIImage) -> Void

    @State private var showCamera = false
    @State private var libraryTapped = false
    @State private var librarySelection: PhotosPickerItem?
    @State private var showURLField = false
    @State private var urlText = ""

    var body: some View {
        Menu {
            if allowedSources.contains(.camera), UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: { Label("Take Photo", systemImage: "camera") }
            }
            if allowedSources.contains(.library) {
                Button { libraryTapped = true } label: { Label("Choose from Library", systemImage: "photo.on.rectangle") }
            }
            if allowedSources.contains(.url) {
                Button { showURLField = true } label: { Label("Paste Image URL", systemImage: "link") }
            }
        } label: {
            Label("Add image", systemImage: "plus.viewfinder")
        }
        .photosPicker(isPresented: $libraryTapped, selection: $librarySelection, matching: .images)
        .fullScreenCover(isPresented: $showCamera) { CameraPicker(onImage: onImage).ignoresSafeArea() }
        .onChange(of: librarySelection) { _, item in Task { await loadLibrary(item) } }
        .alert("Paste image URL", isPresented: $showURLField) {
            TextField("https://…", text: $urlText)
            Button("Cancel", role: .cancel) {}
            Button("Add") { Task { await loadURL() } }
        } message: {
            Text("For Instagram/Pinterest, save the image to Photos first — those sites block direct links.")
        }
    }

    private func loadLibrary(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data) else { return }
        onImage(img)
    }

    private func loadURL() async {
        switch ImageURLValidator.validate(urlText) {
        case .failure(let e):
            await MainActor.run { ErrorBus.shared.report(message(for: e)) }
        case .success(let url):
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let img = UIImage(data: data) { onImage(img) }
                else { await MainActor.run { ErrorBus.shared.report("That link isn't an image.") } }
            } catch {
                await MainActor.run { ErrorBus.shared.report("Couldn't load image — try saving it to Photos instead.") }
            }
        }
    }

    private func message(for e: URLInputError) -> String {
        switch e {
        case .empty: "Enter a URL first."
        case .notHTTP, .malformed: "That doesn't look like a valid web link."
        case .likelyBlockedHost: "Instagram/Pinterest block direct links — save the image to Photos, then use Choose from Library."
        }
    }
}
