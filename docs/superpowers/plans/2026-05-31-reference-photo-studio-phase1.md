# Reference Photo Studio (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the boutique owner seed a Design from a reference photo (camera / library / URL), apply fabric via photo or text description, AI-render the dress in that fabric, and run the existing customer virtual try-on — fixing the app-wide camera-input gap in the process.

**Architecture:** Extend the existing Design pipeline (a Design can be seeded by sketch AND/OR reference photo; everything downstream already keys off `design_renders`). Add a reusable camera-capable `ImageInputPicker`, one pure prompt-builder, one `GeminiService` method, one entry screen, and a customer-link gate. No change to `design_renders`/`design_tryons`/`job_cards`.

**Tech Stack:** SwiftUI, UIKit (`UIImagePickerController` bridge), PhotosUI, Supabase Postgres + Storage, Gemini REST. XcodeGen project regen after new files. XCTest (pure-logic only).

**Spec:** `docs/superpowers/specs/2026-05-31-reference-photo-studio-design.md`

---

## File Structure

**Create:**
- `supabase/migrations/0026_design_reference_image.sql` — column + bucket + RLS (applied via Supabase MCP)
- `ipad/Boutique360/Features/Designs/ImageInputPicker.swift` — reusable camera/library/URL picker + pure URL validator
- `ipad/Boutique360/Features/Designs/ReferenceStudioView.swift` — the entry screen
- `ipad/Boutique360/Features/Designs/CustomerLinkSheet.swift` — customer picker for the VTO gate
- `ipad/Boutique360Tests/ImageURLValidatorTests.swift`
- `ipad/Boutique360Tests/ReferencePromptTests.swift`

**Modify:**
- `ipad/Boutique360/Models/Design.swift` — add `referenceImagePath`
- `ipad/Boutique360/Services/DesignsService.swift` — add `saveReferenceImagePath`
- `ipad/Boutique360/Services/StorageService.swift` — add `designReferences` bucket case + `referencePath`
- `ipad/Boutique360/Services/GeminiService.swift` — add `PromptTemplates.renderGarmentFromReference` + `GeminiService.renderGarmentFromReference`
- `ipad/Boutique360/Features/Designs/VirtualTryOnView.swift` — swap PhotosPicker → ImageInputPicker; add customer-link gate
- `ipad/Boutique360/Features/Designs/SketchCanvasView.swift` — swap `.photosPicker` modifier → ImageInputPicker
- `ipad/Boutique360/Features/Designs/DesignDetailView.swift` — "Start from a photo" button
- `ipad/Boutique360/Features/Designs/DesignsListView.swift` — "+ From inspo photo" entry
- `ipad/Boutique360Tests/ModelDecodingTests.swift` — Design decode with/without reference column

---

## Chunk 1: Data layer (migration, model, services)

### Task 1: Migration — column + bucket + RLS

**Files:**
- Create: `supabase/migrations/0026_design_reference_image.sql`

- [ ] **Step 1: Write the migration SQL**

```sql
-- 0026: reference-photo seed for designs + private storage bucket
alter table public.designs
  add column if not exists reference_image_path text;

insert into storage.buckets (id, name, public)
values ('design-references', 'design-references', false)
on conflict (id) do nothing;

-- Staff-only access, mirroring the design-sketches policy block in 0019.
do $$ begin
  create policy "design-references staff read"
    on storage.objects for select
    using (bucket_id = 'design-references' and auth.role() = 'authenticated');
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "design-references staff write"
    on storage.objects for insert
    with check (bucket_id = 'design-references' and auth.role() = 'authenticated');
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "design-references staff delete"
    on storage.objects for delete
    using (bucket_id = 'design-references' and auth.role() = 'authenticated');
exception when duplicate_object then null; end $$;
```

- [ ] **Step 2: Apply via Supabase MCP**

Use `mcp__supabase__apply_migration` with project_id `tdnwdlrkbrtoxjzcgusg`, name `design_reference_image`, query = the SQL above.
Expected: `{"success":true}`

- [ ] **Step 3: Verify column + bucket exist**

Use `mcp__supabase__execute_sql`:
```sql
select column_name from information_schema.columns
 where table_name='designs' and column_name='reference_image_path';
select id from storage.buckets where id='design-references';
```
Expected: one row each.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0026_design_reference_image.sql
git commit -m "feat(db): designs.reference_image_path + design-references bucket"
```

---

### Task 2: Design model — `referenceImagePath`

**Files:**
- Modify: `ipad/Boutique360/Models/Design.swift`
- Test: `ipad/Boutique360Tests/ModelDecodingTests.swift`

- [ ] **Step 1: Write the failing test** (append to `ModelDecodingTests.swift`)

```swift
func testDesignDecodesWithoutReferencePath() throws {
    let json = """
    {"id":"8a89e7c2-3e25-4b7f-9e8e-d5e10e0e10e0","boutique_id":"8a89e7c2-3e25-4b7f-9e8e-d5e10e0e1002",
     "name":"Sketch one","status":"draft","created_at":"2026-05-31T08:00:00Z","updated_at":"2026-05-31T08:00:00Z"}
    """.data(using: .utf8)!
    let d = try orderDecoder().decode(Design.self, from: json)
    XCTAssertNil(d.referenceImagePath, "Legacy row decodes without reference path")
}

func testDesignDecodesWithReferencePath() throws {
    let json = """
    {"id":"8a89e7c2-3e25-4b7f-9e8e-d5e10e0e10e0","boutique_id":"8a89e7c2-3e25-4b7f-9e8e-d5e10e0e1002",
     "name":"Inspo","status":"draft","reference_image_path":"designs/abc/reference.jpg",
     "created_at":"2026-05-31T08:00:00Z","updated_at":"2026-05-31T08:00:00Z"}
    """.data(using: .utf8)!
    let d = try orderDecoder().decode(Design.self, from: json)
    XCTAssertEqual(d.referenceImagePath, "designs/abc/reference.jpg")
}
```

- [ ] **Step 2: Run — expect FAIL** (`referenceImagePath` doesn't exist yet)

Run: `cd ipad && xcodebuild test -project Boutique360.xcodeproj -scheme Boutique360 -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' -only-testing:Boutique360Tests/ModelDecodingTests 2>&1 | tail -5`
Expected: compile error / FAIL.

- [ ] **Step 3: Add the property + CodingKey**

In `Design` struct, after `sketchImagePath`:
```swift
    var referenceImagePath: String?     // canonical path inside design-references bucket
```
In `CodingKeys`, add:
```swift
        case referenceImagePath = "reference_image_path"
```

- [ ] **Step 4: Run — expect PASS**

Run the same command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ipad/Boutique360/Models/Design.swift ipad/Boutique360Tests/ModelDecodingTests.swift
git commit -m "feat(model): Design.referenceImagePath (forward-compat decode)"
```

---

### Task 3: StorageService — bucket case + path

**Files:**
- Modify: `ipad/Boutique360/Services/StorageService.swift`

- [ ] **Step 1: Add the bucket case**

In `enum Bucket`, after `designRenders`:
```swift
        case designReferences   = "design-references"       // private (staff only)
```

- [ ] **Step 2: Add the deterministic path helper**

Next to `sketchPath`:
```swift
    static func referencePath(designId: UUID) -> String { "designs/\(designId.uuidString)/reference.jpg" }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `cd ipad && xcodebuild build -project Boutique360.xcodeproj -scheme Boutique360 -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' 2>&1 | grep -E "error:|BUILD"`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add ipad/Boutique360/Services/StorageService.swift
git commit -m "feat(storage): design-references bucket + referencePath"
```

---

### Task 4: DesignsService — `saveReferenceImagePath`

**Files:**
- Modify: `ipad/Boutique360/Services/DesignsService.swift`

- [ ] **Step 1: Add the write method** (after `saveSketchPath`)

```swift
    /// Persist the reference image's canonical path. Mirrors saveSketchPath.
    static func saveReferenceImagePath(designId: UUID, path: String) async throws {
        struct ReferencePatch: Encodable { let reference_image_path: String }
        _ = try await SupabaseService.client.from("designs")
            .update(ReferencePatch(reference_image_path: path))
            .eq("id", value: designId)
            .execute()
    }
```

- [ ] **Step 2: Build to verify**

Run the build command from Task 3 Step 3. Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ipad/Boutique360/Services/DesignsService.swift
git commit -m "feat(service): DesignsService.saveReferenceImagePath"
```

---

## Chunk 2: AI layer (pure prompt-builder + Gemini method)

### Task 5: PromptTemplates.renderGarmentFromReference (pure, TDD)

**Files:**
- Modify: `ipad/Boutique360/Services/GeminiService.swift`
- Test: `ipad/Boutique360Tests/ReferencePromptTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Boutique360

final class ReferencePromptTests: XCTestCase {
    func testPromptIncludesGarmentOccasionFabricDescription() {
        let p = PromptTemplates.renderGarmentFromReference(
            garmentType: "lehenga", occasion: "wedding",
            fabricDescription: "emerald Banarasi silk with gold zari",
            fabricImageCount: 2, styleNotes: "heavy border")
        XCTAssertTrue(p.contains("lehenga"))
        XCTAssertTrue(p.contains("wedding"))
        XCTAssertTrue(p.contains("emerald Banarasi silk"))
        XCTAssertTrue(p.contains("heavy border"))
        // references the supplied fabric swatch images
        XCTAssertTrue(p.lowercased().contains("fabric"))
    }

    func testPromptHandlesNilFabricGracefully() {
        let p = PromptTemplates.renderGarmentFromReference(
            garmentType: nil, occasion: nil,
            fabricDescription: nil, fabricImageCount: 0, styleNotes: nil)
        XCTAssertFalse(p.isEmpty)
        XCTAssertTrue(p.lowercased().contains("reference"))
    }
}
```

- [ ] **Step 2: Run — expect FAIL** (method undefined)

Run: `cd ipad && xcodebuild test ... -only-testing:Boutique360Tests/ReferencePromptTests 2>&1 | tail -5`
Expected: compile error.

- [ ] **Step 3: Implement the pure function** (inside `enum PromptTemplates`)

```swift
    static func renderGarmentFromReference(
        garmentType: String?,
        occasion: String?,
        fabricDescription: String?,
        fabricImageCount: Int,
        styleNotes: String?
    ) -> String {
        var p = """
        You are a fashion illustrator. The FIRST image is a reference photo of a \
        garment the customer likes. Recreate that garment as a single photorealistic \
        finished piece, preserving its silhouette, neckline, and overall design.
        """
        if fabricImageCount > 0 {
            p += "\n\nThe next \(fabricImageCount) image(s) are fabric swatches — render the garment in this fabric."
        }
        if let d = fabricDescription, !d.isEmpty { p += "\nFabric: \(d)" }
        if let g = garmentType { p += "\nGarment type: \(g)" }
        if let o = occasion { p += "\nOccasion: \(o)" }
        if let s = styleNotes, !s.isEmpty { p += "\nStyle notes: \(s)" }
        p += "\n\nReturn a single image on a clean white studio background. Do not include the original reference photo's background or any person."
        return p
    }
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add ipad/Boutique360/Services/GeminiService.swift ipad/Boutique360Tests/ReferencePromptTests.swift
git commit -m "feat(ai): PromptTemplates.renderGarmentFromReference + tests"
```

---

### Task 6: GeminiService.renderGarmentFromReference

**Files:**
- Modify: `ipad/Boutique360/Services/GeminiService.swift`

- [ ] **Step 1: Add the method as a peer `static func` inside `enum GeminiService`** (NOT an extension — `generateImage` is `private static` in the enum)

```swift
    /// Render a garment from a reference photo + optional fabric swatches/description.
    static func renderGarmentFromReference(
        reference: UIImage,
        fabricImages: [UIImage] = [],
        fabricDescription: String? = nil,
        garmentType: String?,
        occasion: String?,
        styleNotes: String? = nil
    ) async throws -> UIImage {
        guard !Config.geminiApiKey.isEmpty else { throw GeminiError.notConfigured }
        let prompt = PromptTemplates.renderGarmentFromReference(
            garmentType: garmentType, occasion: occasion,
            fabricDescription: fabricDescription,
            fabricImageCount: fabricImages.count, styleNotes: styleNotes
        )
        // generateImage already enforces the AICostMeter ceiling + header auth.
        return try await generateImage(prompt: prompt, inputImages: [reference] + fabricImages)
    }
```

- [ ] **Step 2: Build to verify** (BUILD SUCCEEDED)

- [ ] **Step 3: Commit**

```bash
git add ipad/Boutique360/Services/GeminiService.swift
git commit -m "feat(ai): GeminiService.renderGarmentFromReference"
```

---

## Chunk 3: Reusable ImageInputPicker (camera fix) + pure URL validator

### Task 7: Pure URL validator (TDD)

**Files:**
- Create: `ipad/Boutique360/Features/Designs/ImageInputPicker.swift` (validator portion first)
- Test: `ipad/Boutique360Tests/ImageURLValidatorTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Boutique360

final class ImageURLValidatorTests: XCTestCase {
    func testValidHTTPSURL() {
        if case .success(let url) = ImageURLValidator.validate("https://example.com/dress.jpg") {
            XCTAssertEqual(url.host, "example.com")
        } else { XCTFail("expected success") }
    }
    func testRejectsEmpty() {
        if case .failure(let e) = ImageURLValidator.validate("   ") { XCTAssertEqual(e, .empty) }
        else { XCTFail("expected empty failure") }
    }
    func testRejectsNonHTTP() {
        if case .failure(let e) = ImageURLValidator.validate("ftp://x/y.jpg") { XCTAssertEqual(e, .notHTTP) }
        else { XCTFail("expected notHTTP failure") }
    }
    func testFlagsBlockedHosts() {
        // Instagram/Pinterest commonly block hot-linking — surfaced as a distinct case.
        if case .failure(let e) = ImageURLValidator.validate("https://www.instagram.com/p/abc/") {
            XCTAssertEqual(e, .likelyBlockedHost)
        } else { XCTFail("expected likelyBlockedHost") }
    }
}
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement the pure validator** (top of `ImageInputPicker.swift`)

```swift
import SwiftUI
import PhotosUI
import UIKit

enum URLInputError: Equatable { case empty, notHTTP, likelyBlockedHost, malformed }

/// Pure, testable URL validation. No global state, no network — just structural checks.
/// ErrorBus toasting happens in the view layer, keeping this unit-test-pure.
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
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add ipad/Boutique360/Features/Designs/ImageInputPicker.swift ipad/Boutique360Tests/ImageURLValidatorTests.swift
git commit -m "feat(picker): pure ImageURLValidator + tests"
```

---

### Task 8: ImageInputPicker UI (camera + library + URL)

**Files:**
- Modify: `ipad/Boutique360/Features/Designs/ImageInputPicker.swift`

- [ ] **Step 1: Add the camera bridge** (`UIViewControllerRepresentable`)

```swift
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
```

- [ ] **Step 2: Add the `ImageInputPicker` SwiftUI view**

```swift
struct ImageInputPicker: View {
    enum Source { case camera, library, url }
    var allowedSources: [Source] = [.camera, .library, .url]
    let onImage: (UIImage) -> Void

    @State private var showCamera = false
    @State private var libraryTapped = false          // grouped here (was declared after body in review draft)
    @State private var librarySelection: PhotosPickerItem?
    @State private var showURLField = false
    @State private var urlText = ""
    @State private var loadingURL = false

    var body: some View {
        Menu {
            if allowedSources.contains(.camera), UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: { Label("Take Photo", systemImage: "camera") }
            }
            if allowedSources.contains(.library) {
                // PhotosPicker can't live inside Menu reliably; use a flag.
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
            loadingURL = true; defer { loadingURL = false }
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
```

- [ ] **Step 3: Regenerate project (new file) + build**

Run: `cd ipad && xcodegen generate && xcodebuild build -project Boutique360.xcodeproj -scheme Boutique360 -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' 2>&1 | grep -E "error:|BUILD"`
Expected: BUILD SUCCEEDED. (If `ErrorBus` reference fails, confirm `import` — it's in the same module, no import needed.)

- [ ] **Step 4: Commit**

```bash
git add ipad/Boutique360/Features/Designs/ImageInputPicker.swift ipad/Boutique360.xcodeproj
git commit -m "feat(picker): ImageInputPicker (camera + library + url)"
```

---

### Task 9: Swap existing library-only pickers → ImageInputPicker

**Files:**
- Modify: `ipad/Boutique360/Features/Designs/VirtualTryOnView.swift`
- Modify: `ipad/Boutique360/Features/Designs/SketchCanvasView.swift`

- [ ] **Step 1: VirtualTryOnView** — replace the `PhotosPicker(selection: $photoSelection, matching: .images)` view (around line 55) with:

```swift
                ImageInputPicker { img in customerImage = img }
```
Remove the now-unused `@State private var photoSelection` and its `.onChange`/`loadPhoto` if no longer referenced. Keep `customerImage`.

- [ ] **Step 2: SketchCanvasView** — replace the `.photosPicker(isPresented:selection:maxSelectionCount:matching:)` modifier + `showPhotoPicker` button with an `ImageInputPicker` whose closure appends a `FabricOverlay`:

```swift
                ImageInputPicker(allowedSources: [.camera, .library]) { img in
                    // BLOCKER-FIX (review #7): FabricOverlay.position is in SCREEN coords
                    // (composeRaster divides by canvasFrame.width), NOT 0..1 normalized.
                    // Match the existing loadFabrics() positioning exactly.
                    fabricOverlays.append(FabricOverlay(
                        image: img,
                        position: CGPoint(x: canvasFrame.midX * 0.6, y: canvasFrame.midY * 0.5),
                        scale: 0.4, rotation: .zero))
                }
```
Remove `showPhotoPicker`, `photoSelection`, and `loadFabrics` if now unused. (URL source omitted for fabric overlays — physical swatch via camera is the real use.) `canvasFrame` is an existing `@State` on the view, so it's in scope inside the closure.

- [ ] **Step 3: Build to verify** (BUILD SUCCEEDED)

- [ ] **Step 4: Run full test suite to confirm no regressions**

Run: `cd ipad && xcodebuild test -project Boutique360.xcodeproj -scheme Boutique360 -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' 2>&1 | tail -4`
Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add ipad/Boutique360/Features/Designs/VirtualTryOnView.swift ipad/Boutique360/Features/Designs/SketchCanvasView.swift
git commit -m "refactor(picker): adopt ImageInputPicker in VTO + Sketch (fixes camera gap)"
```

---

## Chunk 4: ReferenceStudioView + customer gate + entry points

### Task 10: CustomerLinkSheet (the VTO gate)

**Files:**
- Create: `ipad/Boutique360/Features/Designs/CustomerLinkSheet.swift`

- [ ] **Step 1: Build the sheet** — a searchable customer list that returns the chosen customer

```swift
import SwiftUI

/// Presented when an action needs a customer but the Design has none linked.
/// Reuses CustomersService.list; returns the picked customer to the caller.
struct CustomerLinkSheet: View {
    let onPick: (Customer) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var customers: [Customer] = []
    @State private var search = ""
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            List(filtered) { c in
                Button { onPick(c); dismiss() } label: {
                    VStack(alignment: .leading) {
                        Text(c.name).font(.body)
                        if let p = c.phone { Text(p).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search customers")
            .navigationTitle("Link a customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .overlay { if let e = loadError { ContentUnavailableView("Couldn't load", systemImage: "exclamationmark.triangle", description: Text(e)) } }
            .task {
                do { customers = try await CustomersService.list() }
                catch { loadError = error.localizedDescription }
            }
        }
    }
    private var filtered: [Customer] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? customers : customers.filter { $0.name.lowercased().contains(q) || ($0.phone ?? "").contains(q) }
    }
}
```

- [ ] **Step 2: Regen + build** (BUILD SUCCEEDED)

- [ ] **Step 3: Commit**

```bash
git add ipad/Boutique360/Features/Designs/CustomerLinkSheet.swift ipad/Boutique360.xcodeproj
git commit -m "feat(designs): CustomerLinkSheet for VTO gate"
```

---

### Task 11: ReferenceStudioView

**Files:**
- Create: `ipad/Boutique360/Features/Designs/ReferenceStudioView.swift`

- [ ] **Step 1: Build the screen** — reference image + fabric (photo[s] + text) + generate → result with Share/Try-on. Operates on an existing `design` (caller guarantees a Design row exists; see Task 12 for the create-then-upload at the list entry point).

```swift
import SwiftUI

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
                    Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card))
                }
                ImageInputPicker { referenceImage = $0 }
                Text("Add the dress photo the customer liked (camera, library, or paste a link).")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section("Fabric") {
                ForEach(Array(fabricImages.enumerated()), id: \.offset) { _, img in
                    Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 100)
                }
                ImageInputPicker(allowedSources: [.camera, .library]) { fabricImages.append($0) }
                TextField("Or describe it (e.g. emerald Banarasi silk, gold zari)", text: $fabricDescription, axis: .vertical)
                    .lineLimit(1...3)
            }
            Section {
                Button {
                    Task { await generate() }
                } label: {
                    HStack {
                        Label(buttonLabel, systemImage: "sparkles")
                        Spacer(); if isRunning { ProgressView() }
                    }
                }
                .disabled(isRunning || referenceImage == nil || !Config.aiEnabled)
                if referenceImage == nil { Text("Add a reference dress to start.").font(.caption).foregroundStyle(.secondary) }
                if case .failed(let m) = phase { Text(m).font(.caption).foregroundStyle(.red) }
            }
            if let img = resultImage {
                Section("Rendered") {
                    Image(uiImage: img).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: CornerRadius.card))
                    ShareLink(item: Image(uiImage: img), preview: SharePreview("\(design.name) — AI preview", image: Image(uiImage: img))) {
                        Label("Share with customer", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .navigationTitle("Start from a photo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
    }

    private var isRunning: Bool { switch phase { case .calling, .uploading: true; default: false } }
    private var buttonLabel: String {
        switch phase { case .calling: "Asking Gemini (≈30s)…"; case .uploading: "Saving…"; default: "Generate render" }
    }

    @MainActor private func generate() async {
        guard let bid = ctx.boutiqueId, let ref = referenceImage else { return }
        do {
            // Persist the reference (bucket, path) first — best effort, non-fatal for the render itself.
            if let jpeg = ref.jpegData(compressionQuality: 0.85) {
                let path = StorageService.referencePath(designId: design.id)
                _ = try? await StorageService.upload(jpeg, to: .designReferences, path: path, contentType: "image/jpeg")
                try? await DesignsService.saveReferenceImagePath(designId: design.id, path: path)
            }
            phase = .calling
            let result = try await GeminiService.renderGarmentFromReference(
                reference: ref, fabricImages: fabricImages,
                fabricDescription: fabricDescription.isEmpty ? nil : fabricDescription,
                garmentType: design.garmentType, occasion: design.occasion, styleNotes: design.notesMd)
            phase = .uploading
            guard let png = result.pngData() else { phase = .failed("Couldn't encode result"); return }
            let renderId = UUID()
            let path = StorageService.renderPath(renderId: renderId)
            let upload = try await StorageService.upload(png, to: .designRenders, path: path, contentType: "image/png")
            let record = try await DesignRendersService.record(NewDesignRender(
                boutique_id: bid, design_id: design.id, prompt_used: "reference-photo",
                result_image_url: nil, result_image_path: upload.path,
                model_used: "gemini-2.5-flash-image", processing_ms: 0, cost_estimate_usd: 0.04,
                status: RenderStatus.done.rawValue, error_msg: nil))
            resultImage = result; phase = .done; onRendered(record)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
```

- [ ] **Step 2: Regen + build** (BUILD SUCCEEDED). Verify `NewDesignRender` field names match `RenderView.swift` usage — copy that call site exactly if the compiler complains.

- [ ] **Step 3: Commit**

```bash
git add ipad/Boutique360/Features/Designs/ReferenceStudioView.swift ipad/Boutique360.xcodeproj
git commit -m "feat(designs): ReferenceStudioView (reference + fabric → render)"
```

---

### Task 12: Wire entry points + VTO customer gate

**Files:**
- Modify: `ipad/Boutique360/Features/Designs/DesignDetailView.swift`
- Modify: `ipad/Boutique360/Features/Designs/DesignsListView.swift`
- Modify: `ipad/Boutique360/Features/Designs/VirtualTryOnView.swift`

- [ ] **Step 1: DesignDetailView** — add a "Start from a photo" button in the Workflow section, next to "Sketch with Pencil":

```swift
                Button { showReferenceStudio = true } label: {
                    Label("Start from a photo", systemImage: "photo.badge.plus")
                }
```
Add `@State private var showReferenceStudio = false` and a sheet:
```swift
        .sheet(isPresented: $showReferenceStudio) {
            NavigationStack {
                ReferenceStudioView(design: current) { _ in
                    Task { if let u = try? await DesignsService.get(id: current.id) { current = u } }
                }
            }.presentationDetents([.large])
        }
```

- [ ] **Step 2a: DesignsListView — add the EnvironmentObject** (it is NOT currently present; required for `ctx.boutiqueId`)

At the top of `DesignsListView` with the other properties:
```swift
    @EnvironmentObject private var ctx: BoutiqueContext
```

- [ ] **Step 2b: DesignsListView** — add a toolbar item "+ From inspo photo" that does create-then-open:

```swift
    @State private var newReferenceDesign: Design?
    // in toolbar (primaryAction Menu or a second toolbar Button):
    Button {
        Task {
            guard let bid = ctx.boutiqueId else { return }
            let name = "Inspo — \(Date().formatted(date: .abbreviated, time: .omitted))"
            // BLOCKER-FIX (review #1): NewDesign has 8 fields, no defaults; arg ORDER is
            // boutique_id, customer_id, name, status, garment_type, occasion, notes_md, created_by_staff_id.
            if let d = try? await DesignsService.create(NewDesign(
                boutique_id: bid,
                customer_id: nil,
                name: name,
                status: DesignStatus.draft.rawValue,
                garment_type: nil,
                occasion: nil,
                notes_md: nil,
                created_by_staff_id: nil)) {
                newReferenceDesign = d
            }
        }
    } label: { Label("From inspo photo", systemImage: "photo.badge.plus") }
    // sheet:
    .sheet(item: $newReferenceDesign) { d in
        NavigationStack { ReferenceStudioView(design: d) { _ in Task { await load() } } }
    }
```
(`Design: Identifiable` — confirmed, so `.sheet(item:)` works.)

- [ ] **Step 3a: VirtualTryOnView — make `customer` mutable** (BLOCKER-FIX review #4)

It's currently `let customer: Customer?`. The gate assigns to it, so convert to `@State` initialized via `init`:
```swift
    @State private var customer: Customer?
    // add an init that seeds it (keep the existing `let design: Design`):
    init(design: Design, customer: Customer?) {
        self.design = design
        _customer = State(initialValue: customer)
    }
```
No change needed at the `DesignDetailView` call site (`VirtualTryOnView(design: current, customer: customer)`) — the new memberwise-style init has the same signature.

- [ ] **Step 3b: VirtualTryOnView customer gate** — when `customer == nil`, present `CustomerLinkSheet` before allowing try-on:

```swift
    @State private var showCustomerLink = false
    // If customer == nil, the Generate button triggers showCustomerLink = true
    // instead of being hard-disabled.
    .sheet(isPresented: $showCustomerLink) {
        CustomerLinkSheet { picked in
            Task {
                // BLOCKER-FIX (review #2): DesignPatch.customer_id is UUID? (not String),
                // and all six fields must be supplied (no defaults synthesized).
                _ = try? await DesignsService.update(
                    design.id,
                    patch: .init(name: nil, status: nil, garment_type: nil,
                                 occasion: nil, notes_md: nil, customer_id: picked.id))
                customer = picked
            }
        }
    }
```
Adjust `readyToRun` so a nil customer no longer hard-blocks the screen; instead the Generate action routes through the link sheet when `customer == nil`, and proceeds normally once set.

- [ ] **Step 4: Regen + build + full test suite** (BUILD SUCCEEDED, TEST SUCCEEDED)

- [ ] **Step 5: Commit**

```bash
git add ipad/Boutique360/Features/Designs/DesignDetailView.swift ipad/Boutique360/Features/Designs/DesignsListView.swift ipad/Boutique360/Features/Designs/VirtualTryOnView.swift ipad/Boutique360.xcodeproj
git commit -m "feat(designs): entry points for Reference Studio + VTO customer-link gate"
```

---

## Chunk 5: Verification + docs

### Task 13: Manual tap-test script + docs

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `docs/architecture.md` (Service catalogue: note `GeminiService.renderGarmentFromReference`, `DesignsService.saveReferenceImagePath`, `design-references` bucket)

- [ ] **Step 1: Manual test checklist** (run on simulator via Xcode `Cmd+R`, sign in with demo)

  - [ ] Designs list → "From inspo photo" → creates Design, opens studio
  - [ ] Add reference via Library → image shows
  - [ ] Add fabric photo + type a description → Generate → render appears (~20-30s)
  - [ ] Share the render (system sheet appears)
  - [ ] DesignDetail → "Start from a photo" works on an existing Design
  - [ ] VTO on a customer-less reference Design → CustomerLinkSheet appears → pick → proceeds
  - [ ] Camera option hidden on simulator (only Library + URL show) — expected
  - [ ] URL paste of an instagram.com link → friendly "save to Photos" message

- [ ] **Step 2: Update CHANGELOG + architecture.md** (new entry describing the feature + the camera fix)

- [ ] **Step 3: Final full build + test**

Run: `cd ipad && xcodebuild test -project Boutique360.xcodeproj -scheme Boutique360 -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' 2>&1 | tail -4`
Expected: TEST SUCCEEDED, zero warnings.

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md docs/architecture.md
git commit -m "docs: Reference Photo Studio Phase 1 + camera-input fix"
```

---

## Done criteria

- ✅ Migration applied (column + bucket + RLS verified)
- ✅ Reference → fabric (photo/text) → render → VTO loop works on device/simulator
- ✅ Camera capture available app-wide (VTO customer photo, sketch fabric, reference) on real devices
- ✅ All pure-logic units unit-tested; full suite green; clean build
- ✅ Customer-link gate handles reference Designs with no customer
- ✅ URL paste fails gracefully for Instagram/Pinterest
