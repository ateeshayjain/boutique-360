import SwiftUI
import PencilKit
import PhotosUI

/// Apple Pencil sketch canvas with fabric photo overlays.
/// Layers:  bottom → fabric reference images (draggable) → top PencilKit strokes
///
/// PKCanvasView is wrapped in UIViewRepresentable. We expose the drawing via a
/// Binding<PKDrawing> so the parent view can save it. We also rasterize the full
/// composed view (sketch + fabric overlays) to PNG before saving, so the AI
/// renderer gets a single visual input.
struct SketchCanvasView: View {
    let design: Design
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var drawing = PKDrawing()
    @State private var fabricOverlays: [FabricOverlay] = []
    @State private var showPhotoPicker = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var saving = false
    @State private var error: String?
    @State private var canvasFrame: CGRect = .zero

    var body: some View {
        ZStack {
            GeometryReader { geo in
                ZStack {
                    Color(.systemBackground)

                    // Fabric overlays underneath the strokes
                    ForEach($fabricOverlays) { $overlay in
                        FabricOverlayView(overlay: $overlay)
                    }

                    // PencilKit canvas on top
                    PencilCanvas(drawing: $drawing)
                        .background(Color.clear)
                        .allowsHitTesting(true)
                }
                .onAppear { canvasFrame = geo.frame(in: .local) }
            }
        }
        .navigationTitle("Sketch")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                Button(saving ? "Saving…" : "Save") { Task { await save() } }
                    .disabled(saving)
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    showPhotoPicker = true
                } label: {
                    Label("Add fabric", systemImage: "square.grid.3x3.square")
                }
                Spacer()
                Button(role: .destructive) {
                    drawing = PKDrawing()
                } label: {
                    Label("Clear strokes", systemImage: "arrow.uturn.backward.circle")
                }
                Spacer()
                Button {
                    if !fabricOverlays.isEmpty { fabricOverlays.removeLast() }
                } label: {
                    Label("Remove last fabric", systemImage: "square.slash")
                }.disabled(fabricOverlays.isEmpty)
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoSelection, maxSelectionCount: 3, matching: .images)
        .onChange(of: photoSelection) { _, items in
            Task { await loadFabrics(from: items) }
        }
        .alert("Couldn't save", isPresented: .constant(error != nil), actions: {
            Button("OK") { error = nil }
        }, message: {
            Text(error ?? "")
        })
        .task { await loadExisting() }
    }

    private func loadFabrics(from items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                let overlay = FabricOverlay(
                    image: img,
                    position: CGPoint(x: canvasFrame.midX * 0.6, y: canvasFrame.midY * 0.5),
                    scale: 0.4,
                    rotation: .zero
                )
                fabricOverlays.append(overlay)
            }
        }
        photoSelection = []
    }

    private func loadExisting() async {
        // If the design has a stored sketch_strokes_json, decode + assign to drawing.
        // Stored as base64 of PKDrawing.dataRepresentation() in JSONB { "data": "..." }
        // Simple impl: skipped for v1 since we save full raster — strokes are an
        // optimization for round-trip editing.
    }

    @MainActor
    private func save() async {
        saving = true; defer { saving = false }
        // 1) Compose the full canvas into a PNG (strokes + fabric overlays).
        let composed = await composeRaster()
        guard let png = composed.pngData() else {
            error = "Could not capture canvas"
            return
        }
        // 2) Upload to Storage
        do {
            let path = StorageService.sketchPath(designId: design.id)
            let url = try await StorageService.upload(png, to: .designSketches, path: path, contentType: "image/png")
            // 3) Save URL + stroke data on the design
            let strokes = drawing.dataRepresentation().base64EncodedString()
            _ = try await DesignsService.update(design.id, patch: .init(status: DesignStatus.draft.rawValue))
            // Update sketch_image_url separately — needs a custom patch (status reuse OK for now)
            _ = try await SupabaseService.client.from("designs")
                .update(["sketch_image_url": url, "sketch_strokes_json": "{\"data\":\"\(strokes)\"}"])
                .eq("id", value: design.id)
                .execute()
            onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Render the live canvas (overlays + strokes) into a single UIImage.
    @MainActor
    private func composeRaster() async -> UIImage {
        let size = CGSize(width: 1024, height: 1024)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            // White background (good for AI input)
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // Scale + draw fabric overlays
            for overlay in fabricOverlays {
                let scaledW = size.width * CGFloat(overlay.scale)
                let scaledH = scaledW * overlay.image.size.height / overlay.image.size.width
                let centerX = size.width * (overlay.position.x / max(canvasFrame.width, 1))
                let centerY = size.height * (overlay.position.y / max(canvasFrame.height, 1))
                let rect = CGRect(
                    x: centerX - scaledW / 2,
                    y: centerY - scaledH / 2,
                    width: scaledW,
                    height: scaledH
                )
                overlay.image.draw(in: rect)
            }

            // Stroke layer on top
            let strokeImage = drawing.image(from: CGRect(origin: .zero, size: canvasFrame.size), scale: 2.0)
            strokeImage.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - PencilKit wrapper

struct PencilCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = drawing
        canvas.tool = PKInkingTool(.pen, color: .black, width: 4)
        canvas.alwaysBounceVertical = false
        canvas.drawingPolicy = .anyInput   // works in simulator (finger) + Pencil
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.delegate = context.coordinator

        if let window = canvas.window, let toolPicker = PKToolPicker.shared(for: window) {
            toolPicker.setVisible(true, forFirstResponder: canvas)
            toolPicker.addObserver(canvas)
            canvas.becomeFirstResponder()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = canvas.window, let toolPicker = PKToolPicker.shared(for: window) {
                toolPicker.setVisible(true, forFirstResponder: canvas)
                toolPicker.addObserver(canvas)
                canvas.becomeFirstResponder()
            }
        }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.drawing = drawing
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvas
        init(_ p: PencilCanvas) { parent = p }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}

// MARK: - Fabric overlay

struct FabricOverlay: Identifiable {
    let id = UUID()
    let image: UIImage
    var position: CGPoint
    var scale: CGFloat            // relative to parent width (0...1)
    var rotation: Angle
}

struct FabricOverlayView: View {
    @Binding var overlay: FabricOverlay

    @State private var dragOffset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        Image(uiImage: overlay.image)
            .resizable()
            .scaledToFit()
            .frame(width: 200 * overlay.scale * 2)
            .rotationEffect(overlay.rotation)
            .position(x: overlay.position.x + dragOffset.width, y: overlay.position.y + dragOffset.height)
            .gesture(
                DragGesture()
                    .onChanged { dragOffset = $0.translation }
                    .onEnded { value in
                        overlay.position = CGPoint(
                            x: overlay.position.x + value.translation.width,
                            y: overlay.position.y + value.translation.height
                        )
                        dragOffset = .zero
                    }
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { value in overlay.scale = max(0.1, min(1.5, lastScale * value)) }
                    .onEnded { _ in lastScale = overlay.scale }
            )
            .shadow(radius: 3)
    }
}
