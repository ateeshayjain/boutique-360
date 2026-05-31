# Reference Photo Studio — Design Spec

**Date:** 2026-05-31
**Status:** Approved (pending spec review)
**Author:** Brainstormed with Ateeshay Jain

---

## Problem

Today the AI design pipeline is **sketch-first**: the owner must hand-draw a garment with Apple Pencil before they can AI-render it, apply fabric, or do a virtual try-on. But the most common real consultation starts with *"I saw this dress on Instagram/Pinterest"* — a reference photo, not a blank canvas.

The owner wants to:
1. Bring in a reference dress image (from Pinterest / Instagram / camera roll)
2. Apply a fabric to it and see the dress rendered in that fabric
3. Add a customer photo and see the customer wearing that dress

The underlying AI plumbing already supports this (`GeminiService.generateImage(prompt:, inputImages:)` accepts an arbitrary image array; `virtualTryOn` exists). The gap is the **entry point** and a **camera-capable image picker**.

A data-inflow audit (2026-05-31) also found:
- The only image input today is the Photos **library** picker (`PHPicker`), which cannot capture a new photo. `NSCameraUsageDescription` is declared in Info.plist but **no code uses the camera.**
- This blocks "snap the fabric swatch / customer on the spot" across the whole app, not just this feature.

---

## Goals

- Let the owner seed a Design from a **reference photo** instead of (or in addition to) a sketch.
- Apply fabric via **photo, saved library, or text description** — any combination.
- Flow seamlessly into the existing **render → virtual try-on → job card → WhatsApp share** pipeline.
- Fix the app-wide **camera gap** with one reusable picker.
- A reference session produces a **saved Design** (customer link optional).

## Non-goals

- No Pinterest/Instagram API integration (their APIs don't allow it for a small app). Image entry is via Photos picker / URL paste / Share Extension.
- No change to the existing sketch flow's behavior (it remains a peer path).
- No new analytics, no batch generation.

---

## Approach

**Extend the existing Design pipeline** (chosen over a separate "AI Studio" module or a minimal RenderView hack). A Design can be *seeded* by a sketch **and/or** a reference photo. Everything downstream already keys off the render output, so render-with-fabric, VTO, job card, and WhatsApp share work unchanged.

This reuses the entire data model and pipeline; the only genuinely new pieces are a reusable image picker, one entry screen, and one Gemini method.

---

## Architecture

### Component 1 — `ImageInputPicker` (reusable, fixes the camera gap)

A small SwiftUI component that presents a source menu: **Take Photo (camera) · Choose from Library · Paste URL**. Returns a `UIImage`.

- **Camera**: `UIImagePickerController` wrapped in `UIViewControllerRepresentable` with `sourceType = .camera`. Guarded by `UIImagePickerController.isSourceTypeAvailable(.camera)` so it's hidden on simulators / camera-less devices, where only Library + URL show.
- **Library**: existing `PhotosPicker` (`.images`).
- **URL**: text field → a **pure** validator helper `func validatedImageURL(_ raw:String) -> Result<URL, URLInputError>` (unit-testable, no global state) → `URLSession` fetch → `UIImage`. **ErrorBus toasting happens in the view layer**, not in the pure helper, so the validator stays pure for tests. The blocked-host case (Instagram/Pinterest hot-link block) produces a clear message pointing the owner to Save-to-Photos / Share Extension.

This component **replaces the two existing library-only pickers**, which use *different APIs*:
- `VirtualTryOnView` (line 55) uses the `PhotosPicker` **view** directly → swap the view.
- `SketchCanvasView` uses the `.photosPicker(isPresented:selection:maxSelectionCount:matching:)` **modifier** + a `showPhotoPicker` bool + `[PhotosPickerItem]` binding → replace the modifier and its state.
Both are library-only (no camera today), so the camera gap is fixed app-wide.

**What it does:** returns one user-supplied image from camera, library, or URL.
**How you use it:** `ImageInputPicker(allowedSources: [.camera, .library, .url]) { image in ... }`
**Depends on:** UIKit (UIImagePickerController), PhotosUI, URLSession, ErrorBus.

### Component 2 — `GeminiService.renderGarmentFromReference(...)`

```swift
static func renderGarmentFromReference(
    reference: UIImage,
    fabricImages: [UIImage],        // 0..n fabric photos / library picks
    fabricDescription: String?,     // optional text fabric description
    garmentType: String?,
    occasion: String?,
    styleNotes: String?
) async throws -> UIImage
```

The prompt is built by a **pure function** `PromptTemplates.renderGarmentFromReference(garmentType:, occasion:, fabricDescription:, fabricImageCount:, styleNotes:) -> String` (extracted so it's unit-testable without the network, mirroring the existing `PromptTemplates` enum). The method then calls the existing `generateImage(prompt:, inputImages: [reference] + fabricImages)`. **Implementation note:** `generateImage` is `private static` inside the `GeminiService` enum, so `renderGarmentFromReference` must be added as a **peer `static func` within `GeminiService`** (not an extension in another file). Subject to the existing `AICostMeter` daily cost ceiling. Output is uploaded as a normal `design_renders` row.

**What it does:** composites reference dress + fabric into a new garment render.
**How you use it:** one call; returns the rendered UIImage.
**Depends on:** `generateImage`, `AICostMeter`, `PromptTemplates`.

### Component 3 — `ReferenceStudioView` (entry screen)

A `Form`-style sheet with three stacked sections + a generate action:

1. **Reference image** — `ImageInputPicker`. Shows the chosen image; required to proceed.
2. **Fabric** — any combination of: `ImageInputPicker` (snap/library) for swatch photos, and a free-text description field. All optional individually; at least one recommended.
   - **Scope correction (from spec review):** a *browsable saved fabric library* does **not** exist today — fabric input across the app is currently photo-only (there is no `FabricsService`/`Fabric` model or fabric-catalog UI). So Phase 1 ships fabric via **photo + text description**. The "pick from saved fabric library" source is **deferred to Phase 4**, which must first build a minimal `FabricsService` + fabric-catalog list backed by the existing `fabrics` storage bucket. This keeps Phase 1 honest and unblocked.
3. **Generate** — calls `renderGarmentFromReference`, shows progress (~20-30s), then the result with the existing **Share** + **Try on customer** actions.

Reached from:
- **"Start from a photo"** button next to "Sketch with Pencil" in `DesignDetailView` (a Design already exists here — just upload + patch).
- **"+ From inspo photo"** action on the Designs list. **Create-then-upload ordering** (the reference upload needs a `design.id`): (1) insert a Design row via `DesignsService.create(NewDesign(...))` with an auto-name like *"Inspo — {date}"* (editable later in `DesignFormView`), (2) get its `id`, (3) upload the reference to `design-references/{id}`, (4) `DesignsService.saveReferenceImagePath(designId:path:)`. This mirrors how the sketch flow relies on an existing Design before writing the sketch path.

**What it does:** orchestrates reference + fabric inputs into a saved render.
**Depends on:** `ImageInputPicker`, `GeminiService.renderGarmentFromReference`, `DesignsService`, `StorageService`, `DesignRendersService`.

### Component 4 — Downstream (one small change)

Render → **Try on customer** → `JobCardComposerView` → WhatsApp share. All operate on `design_renders`.

**Spec-review correction:** `VirtualTryOnView` today hard-requires a non-nil customer (`readyToRun` checks `customer != nil`), so a Design seeded by a reference photo with **no customer linked** cannot reach VTO. Phase 1 adds a thin gate: when the owner taps **Try on customer** on a customer-less Design, present a **customer picker sheet** (reuses `CustomersService.list` + the existing customer-search list) that links the chosen customer to the Design (`designs.customer_id`) before opening `VirtualTryOnView`. If a customer is already linked, go straight to VTO. This is the only downstream code change; it's small and also benefits the existing sketch flow.

---

## Data model & storage

- **Migration `0026_design_reference_image.sql`** (next free file number — disk has `…0019`, `0025`; cloud-applied via Supabase MCP per recent practice). It does **three** things, mirroring how `0019_storage_buckets.sql` provisions buckets:
  1. `alter table designs add column if not exists reference_image_path text;`
  2. `insert into storage.buckets (id, name, public) values ('design-references','design-references', false) on conflict do nothing;`
  3. staff-only RLS policies on that bucket, copied from the `design-sketches` policy block in `0019`.
- `Design` model gains `referenceImagePath: String?` (Codable key `reference_image_path`), decoding nil for legacy rows (forward-compatible, matching `defaultGstRate` / `gstRate`).
- **`DesignsService.saveReferenceImagePath(designId:path:)`** — the write path (analogous to the existing `DesignsService.saveSketchPath(...)`). This is the method the data-flow diagram's "designs.reference_image_path" step calls; without it the column is never populated.
- No change to `design_renders`, `design_tryons`, `job_cards`.
- Persist **(bucket, path)** per the existing signed-URL discipline; never persist signed URLs.

---

## Data flow

```
Reference image (camera/library/URL)
        │  ImageInputPicker → UIImage
        ▼
   upload → design-references bucket; designs.reference_image_path
        │
Fabric (photo/library/text)  ──┐
        │                       │
        ▼                       ▼
GeminiService.renderGarmentFromReference(reference, fabricImages, fabricDescription, …)
        │  (AICostMeter ceiling check → generateImage multi-image)
        ▼
   result PNG → upload → design-renders bucket → design_renders row
        │
        ▼
VirtualTryOnView (customer photo via ImageInputPicker) → design_tryons (7-day purge)
        │
        ▼
JobCard PDF / WhatsApp share  (existing)
```

---

## Error handling

- **Cost ceiling**: `renderGarmentFromReference` goes through `AICostMeter`; hitting the cap surfaces the existing friendly toast.
- **URL fetch failure** (IG/Pinterest hot-link block): caught → `ErrorBus` toast suggesting Save-to-Photos / Share Extension.
- **Camera unavailable** (simulator): source hidden, no crash.
- **Gemini failure / blank result**: existing `.failed(msg)` phase handling, reused.
- **Missing reference**: Generate disabled until a reference image is present.
- **Upload failure**: surfaced via `ErrorBus`; render not recorded.
- **DPDP consent (camera-sourced customer photo)**: capturing the customer photo via camera vs. library is the **same consent surface** — `VirtualTryOnView`'s existing consent capture (timestamp recorded *before* any processing, 7-day purge) is unchanged and applies regardless of image source. The camera does not create a new compliance path.

---

## Testing

- **Unit (pure logic)**: `ImageInputPicker` URL-validation helper (valid/invalid/blocked-host messaging); `PromptTemplates.renderGarmentFromReference` (asserts garment type, occasion, fabric description, and fabric-image count are all represented in the prompt; handles nil fabric gracefully); `Design` decode with/without `reference_image_path` (forward-compat, matching existing `ModelDecodingTests` pattern).
- **Build-verified**: the SwiftUI screens, the UIKit camera wrapper, and the customer-picker gate.
- **Manual tap-test** (on device/simulator): camera capture, library pick, URL paste, fabric combinations, customer-link gate, full loop to VTO.
- Network/Gemini integration remains manual (consistent with existing policy in `docs/testing-guide.md`).

---

## Phased delivery

| Phase | Scope | Outcome |
|---|---|---|
| **1 — Core** | Migration + `design-references` bucket + `Design.referenceImagePath` + `ImageInputPicker` (Camera + Library) + `PromptTemplates.renderGarmentFromReference` + `GeminiService.renderGarmentFromReference` + `ReferenceStudioView` (reference + fabric via **photo & text**) + customer-link gate + wire into existing VTO. Replace bare PhotosPicker in VTO + Sketch with `ImageInputPicker`. | The full reference-photo → fabric (photo/text) → customer try-on loop, plus camera fixed app-wide. |
| **2 — URL paste** | URL source in `ImageInputPicker` with graceful IG/Pinterest fallback. | Paste-a-link entry. |
| **3 — Share Extension** | New app-extension target so "Share → Boutique 360" appears in Instagram/Pinterest, feeding `ReferenceStudioView`. | Direct share-in. |
| **4 — Fabric library** | Minimal `FabricsService` + `Fabric` model + fabric-catalog list (backed by the `fabrics` bucket), added as a third fabric source in `ReferenceStudioView` (and reusable in the sketch flow). | Pick from saved fabrics. |

Phase 1 delivers the full loop the owner described (with fabric via photo + text). Phases 2-4 are additive: paste-a-link, direct share-in, and the saved fabric library.

---

## Open questions resolved during brainstorming

- **Image source** → all three (Photos core, Share Extension, URL paste), phased.
- **Fabric source** → all three (photo, library, text).
- **Save behavior** → saved Design, customer optional.
- **Camera permission** → keep `NSCameraUsageDescription`, now actually used by `ImageInputPicker`.

---

## Risks

| Risk | Mitigation |
|---|---|
| Gemini reference-render quality varies (it's interpreting a real photo, not a clean sketch) | Prompt tuning; the owner can regenerate; fabric description adds steering |
| URL paste unreliable for IG/Pinterest specifically | Documented + graceful fallback to Save-to-Photos / Share Extension |
| Camera capture adds a UIKit bridge (more surface) | Small, well-isolated `UIViewControllerRepresentable`; guarded by availability check |
| Reference photo may depict a copyrighted design | Out of scope — owner's professional responsibility, same as today's manual reference use |
