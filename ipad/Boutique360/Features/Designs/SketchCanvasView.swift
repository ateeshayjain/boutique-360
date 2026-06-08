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
    @State private var saving = false
    @State private var error: String?
    @State private var canvasFrame: CGRect = .zero
    // Wave 5: optional template guide rendered as a faint dashed outline
    // BELOW fabric overlays + strokes. Nil = no template, freeform canvas.
    @State private var template: GarmentTemplate?

    var body: some View {
        ZStack {
            GeometryReader { geo in
                ZStack {
                    Color(.systemBackground)

                    // Wave 5: garment template guide BELOW everything.
                    // `allowsHitTesting(false)` inside the overlay so
                    // strokes still register on the PencilKit layer.
                    if let t = template {
                        GarmentTemplateOverlay(template: t)
                    }

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
                // Camera + Library fabric input (fixes the library-only camera gap).
                ImageInputPicker(allowedSources: [.camera, .library]) { img in
                    addFabricOverlay(img)
                }
                Spacer()
                // Wave 5: garment template picker. Menu so it's one tap
                // to pick / remove without leaving the canvas.
                Menu {
                    Button("No template") { template = nil }
                    Divider()
                    ForEach(GarmentTemplate.allCases) { t in
                        Button(t.displayName) { template = t }
                    }
                } label: {
                    Label(template?.displayName ?? "Template",
                          systemImage: template == nil ? "rectangle.dashed" : "rectangle.dashed.and.paperclip")
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
        .alert("Couldn't save", isPresented: .constant(error != nil), actions: {
            Button("OK") { error = nil }
        }, message: {
            Text(error ?? "")
        })
        .task { await loadExisting() }
    }

    /// Places a fabric overlay near the upper-left of the canvas. Position is in
    /// SCREEN coords (composeRaster divides by canvasFrame.width), matching the
    /// prior multi-select behavior — just one image at a time now.
    private func addFabricOverlay(_ img: UIImage) {
        let overlay = FabricOverlay(
            image: img,
            position: CGPoint(x: canvasFrame.midX * 0.6, y: canvasFrame.midY * 0.5),
            scale: 0.4,
            rotation: .zero
        )
        fabricOverlays.append(overlay)
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
        // 2) Upload to Storage and persist the (bucket, path) — not the short-lived signed URL.
        do {
            let path = StorageService.sketchPath(designId: design.id)
            let upload = try await StorageService.upload(png, to: .designSketches, path: path, contentType: "image/png")
            try await DesignsService.saveSketchPath(designId: design.id,
                                                    path: upload.path,
                                                    cachedURL: upload.immediateURL,
                                                    strokes: drawing.dataRepresentation())
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

            // Wave 5: bake the template outline into the raster so the AI
            // renderer sees the silhouette the designer was tracing. Faint
            // (alpha 0.25) so it nudges the AI without dominating strokes.
            if let t = template {
                let path = t.path(in: CGRect(origin: .zero, size: size))
                UIColor.gray.withAlphaComponent(0.25).setStroke()
                let cg = ctx.cgContext
                cg.setLineWidth(2.0)
                cg.setLineDash(phase: 0, lengths: [10, 6])
                cg.addPath(path.cgPath)
                cg.strokePath()
                cg.setLineDash(phase: 0, lengths: [])    // reset for downstream draws
            }

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

        // iOS 14+: each scene owns its own PKToolPicker — `PKToolPicker.shared(for:)`
        // was deprecated because it tied the picker's lifecycle to a window. The
        // coordinator holds the strong reference so it survives view updates.
        let toolPicker = context.coordinator.toolPicker
        toolPicker.setVisible(true, forFirstResponder: canvas)
        toolPicker.addObserver(canvas)
        canvas.becomeFirstResponder()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            toolPicker.setVisible(true, forFirstResponder: canvas)
            toolPicker.addObserver(canvas)
            canvas.becomeFirstResponder()
        }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.drawing = drawing
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvas
        /// Own this picker so its lifetime matches the view. Without a strong
        /// reference here, the picker would deallocate immediately and never show.
        let toolPicker = PKToolPicker()
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
