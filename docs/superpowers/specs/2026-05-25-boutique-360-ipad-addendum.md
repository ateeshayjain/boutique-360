# Boutique 360 iPad App — Spec Addendum

**Date:** 2026-05-25
**Status:** Approved (user override: "stop asking, start building")
**Parent spec:** `2026-05-25-boutique-360-design.md`
**Relationship:** This addendum **adds an iPad app surface** to the parent spec. The web admin CRM + public storefront + Supabase backend from the parent spec remain in scope unchanged. All three surfaces share one Supabase backend.

---

## 1. Why iPad-native

The iPad app is the **commercial differentiator**. The web pieces (admin CRM + public storefront) are necessary infrastructure but exist elsewhere in the market. The iPad workflow does not.

The workflow being digitized: a boutique designer sits with a customer, sketches a garment with a pen on paper, attaches a fabric swatch, writes measurements in the margin, then either explains "this is what it'll look like" or shows reference photos. The customer signs off on imagination.

We replace that with: **sketch on iPad with Apple Pencil → attach fabric photo → write measurements on the same canvas → tap "Render" → AI generates photorealistic garment → tap "Try on" → AI dresses the customer's photo in the garment.** The customer signs off on a near-final visualization, not their imagination.

This is a single coherent workflow. Not four loose features.

## 2. Build order (settled)

1. **Backend Foundation** (new Plan 1) — Supabase only, no Next.js. Schema serves iPad immediately, web later.
2. **iPad App Foundation** (Plan 2) — Xcode project, SwiftUI scaffolding, Supabase Swift SDK, auth.
3. **iPad Design Canvas** (Plan 3) — PencilKit, fabric attach, measurement layer, local persistence.
4. **iPad AI Pipeline** (Plan 4) — Sketch + fabric + measurements → Gemini → garment render. VTO call.
5. **iPad CRM + Catalog** (Plan 5) — Customers, products, inquiries, orders on iPad.
6. **Web Admin CRM** (Plans 6-7) — pulls from parent spec, refocused (no Plan-1 backend work duplicated).
7. **Public Website** (Plan 8) — pulls from parent spec.
8. **Automation + Messaging** (Plan 9) — Interakt + journeys, used by all surfaces.
9. **Payments + Invoicing** (Plan 10) — Razorpay, used by web checkout.

## 3. iPad app architecture

### Stack
- **SwiftUI** (iOS 17+, iPad-only, optimized for 11" and 13" iPad Pro)
- **PencilKit** for sketch canvas + handwriting recognition (Apple's Vision/Text framework for OCR of measurements)
- **SwiftData** for local-first persistence (offline support; sync to Supabase when online)
- **Supabase Swift SDK** for auth, Postgres, Storage, Realtime
- **AVFoundation** for camera (fabric capture, customer photo)
- **PhotosUI** for photo library picker
- **Combine** for reactive bindings
- **CryptoKit** for at-rest encryption of customer photos before storage

### Why SwiftUI over UIKit
- iOS 17+ SwiftUI has matured enough for production iPad apps
- Faster iteration, less boilerplate
- Better Apple Pencil + PencilKit integration story
- Easier to adopt new Apple frameworks (Visual Intelligence, App Intents, Live Activities) over time

### Why not cross-platform (React Native / Flutter)
- PencilKit has no parity equivalent for pressure/tilt/latency
- Apple Pencil ProMotion (120Hz refresh) needs first-party integration
- VTO + camera pipeline benefits from native AVFoundation
- Single-platform (iPad) sales focus — we lose nothing skipping Android tablets for a boutique market

### Major modules

| Module | Owns | Notable |
|---|---|---|
| `Auth` | Magic-link sign-in via Supabase, universal-link callback | Same Supabase Auth as web; one staff_user row per device |
| `DesignCanvas` | PencilKit canvas, fabric photo overlay, measurement layer, color picker, stroke history | Single coherent canvas — sketch + fabric + measurements coexist |
| `MeasurementCapture` | Handwriting recognition via Vision → structured measurements (bust, waist, etc.) | OCRs handwritten numbers from canvas margin; falls back to manual entry |
| `FabricGallery` | Camera + photo library picker, fabric metadata (name, supplier, cost), reusable across designs | Designer captures swatch once, reuses for multiple designs |
| `AIRenderer` | Calls Gemini with sketch + fabric refs + style hints → returns garment render | Async with queue UI, retries, cost tracking |
| `VirtualTryOn` | Customer photo capture (with consent prompt) + garment render → Gemini → result | In-store demo; result is watermarked + auto-purged after 7 days unless saved |
| `CustomerProfile` | Browse/search customers, view history, link new design to customer | Mini-CRM scoped to in-store use; full CRM is the web admin |
| `InquiryComposer` | Convert a saved design into an inquiry row → syncs to backend → web admin sees it | The bridge between design tool and back-office |
| `SyncEngine` | Push local SwiftData changes to Supabase; pull updates; conflict resolution | Offline-first; CRDT-lite (last-write-wins per field, except measurements which are append-only) |
| `Settings` | Boutique branding, AI model preference (flash vs imagen), watermark text, sync status | Per-device settings; org-wide settings come from Supabase |

### Data model additions (Postgres, extends parent spec)

The parent spec covers customers, products, orders, inquiries, vto_sessions, design_generations, etc. The iPad workflow adds these structures:

```sql
-- Captured fabric swatches; reusable across designs
fabrics
  id, boutique_id, name, supplier, color_hex, cost_per_meter,
  photo_url, captured_by_staff_id, captured_at, retired_at (nullable)

-- A design originated on the iPad; may evolve into a product or stay as a one-off concept
designs
  id, boutique_id, customer_id (nullable for spec work),
  name, status ('draft'|'rendered'|'shared_with_customer'|'approved'|'in_production'|'delivered'|'archived'),
  sketch_strokes_json,           -- PencilKit drawing data, exportable
  sketch_image_url,              -- rasterized for backend/web preview
  measurements_json,             -- structured measurements (whether OCR'd or manual)
  garment_type, occasion, notes_md,
  created_by_staff_id, created_at, updated_at

-- Many-to-many: a design references multiple fabrics
design_fabrics
  design_id, fabric_id, role ('main'|'lining'|'trim'|'embellishment'),
  meters_estimated, sort_order

-- AI renders generated from a design (1 design → many render attempts)
design_renders
  id, design_id,
  prompt_used,                   -- includes sketch + fabric descriptions + style hints
  result_image_url, model_used, processing_ms, cost_estimate_usd,
  status ('queued'|'done'|'failed'), error_msg,
  is_favorite bool default false,
  parent_render_id (nullable, fk self),  -- iteration tree
  created_at

-- Customer try-on sessions tied to a specific design render
design_tryons
  id, design_render_id, customer_id,
  customer_photo_url,            -- ephemeral; auto-purge after 7 days unless saved
  result_image_url,               -- watermarked
  model_used, processing_ms, cost_estimate_usd,
  customer_consent_signed_at,    -- DPDP consent capture
  saved_to_lookbook bool default false,
  created_at, purge_at           -- auto-purge customer_photo_url at this time

-- Sync state for iPad clients (offline-first)
device_sync_state
  device_id (uuid generated on first install), staff_user_id,
  last_synced_at, last_event_id_seen, app_version,
  ios_version, device_model
```

Parent spec's `vto_sessions` table now describes **web-initiated** try-ons (anon visitors on the public website); iPad try-ons use `design_tryons` because they're tied to a designer-created concept, not a published product. Both write to the unified `events` table.

### Sync strategy (offline-first)

The iPad must work in a boutique with flaky 4G. Approach:

- **Writes:** All user actions write to local SwiftData first. A background `SyncEngine` task uploads pending writes when online. Reachability detected via `NWPathMonitor`.
- **Reads:** Local SwiftData is the source of truth for the UI. SyncEngine pulls remote changes since `last_event_id_seen` and merges.
- **Images:** Captured locally first (file URL in SwiftData), uploaded to Supabase Storage in background. Local file kept until upload confirmed.
- **Conflict resolution:**
  - Last-write-wins per field for: design name, notes, status
  - Append-only for: measurements (each measurement gets its own row with timestamp), strokes (PencilKit drawing is monolithic; remote version wins if local hasn't changed)
  - Never overwrite: customer photos (immutable once captured)
- **AI calls:** Always require network. Queue if offline, surface "will render when connection returns."

### Auth flow

1. Owner installs app, opens, sees "Sign in to Boutique 360"
2. Enters email → Supabase sends magic link
3. Magic link URL is a **universal link** (`https://app.boutique360.com/auth/callback?token=…`) → opens the iPad app, exchanges token, signs in
4. App stores session in iOS Keychain, refreshes silently
5. Subsequent launches restore session from Keychain
6. Sign-out clears Keychain + local SwiftData (for shared-device scenarios)

### Customer-facing surface on iPad

When the designer hands the iPad to the customer (e.g., to choose a VTO photo, or to review the render), there's a **Customer Mode** toggle that:
- Locks navigation to the current design / render / try-on view
- Hides pricing, internal notes, other customers' data
- Requires staff PIN to exit
- Auto-exits after 5 minutes of inactivity

### Privacy (DPDP-critical)

- Customer photos: never uploaded without on-screen consent capture (signature field)
- Customer photo auto-purge after 7 days unless explicitly saved to a `design_tryons.saved_to_lookbook = true` record (and even then, customer can request deletion anytime)
- Watermark on every VTO result before showing/sharing
- All customer photo URLs are signed + expire after 1 hour; never cacheable
- iPad-side: customer photos stored in Files app secure enclave, not Photo Library; deleted on auto-purge

## 4. Integrations specific to iPad

Same as parent spec for: Supabase, Gemini, Razorpay (only used from web checkout).
Added by iPad:
- **App Store Connect** for distribution (TestFlight for staging, App Store for production)
- **Universal Links** via apple-app-site-association file hosted at `https://app.boutique360.com/.well-known/apple-app-site-association`
- **Push notifications** via APNs (Apple Push Notification service) → for "render complete" alerts when AI was queued offline; managed via Supabase Realtime → APNs adapter (Inngest function)

## 5. Distribution

- **Internal dev:** local builds via Xcode on owner's iPad
- **Staging:** TestFlight, 5-10 designer invitees
- **Production:** App Store (B2C-style listing — "Boutique 360 for designers"; or Custom App Distribution for direct-to-business if it's only the one client)
- **Bundle ID:** `com.boutique360.designer`
- **Apple Developer Program:** $99/yr — client homework, like Meta Business

## 6. Success criteria

- [ ] Designer can complete the full workflow (sketch → fabric → measurements → render → VTO) in **under 5 minutes** for a familiar garment type
- [ ] Sketch-to-render latency p95 **under 45 seconds** (Gemini call + image download)
- [ ] VTO latency p95 **under 30 seconds**
- [ ] App works fully **without network** for sketching/fabric/measurements; only AI calls block on connectivity
- [ ] Sync recovers cleanly after a 24h offline period with zero data loss
- [ ] Customer Mode passes a "would you hand this to a stranger" test (no PII leak from other customers visible)
- [ ] App passes App Store review (or Custom App Distribution review) without significant rework

## 7. Out of scope (v1)

- iPhone version (iPad-only)
- Apple Watch companion
- macOS Catalyst (different UX)
- Generative video try-on (only static images in v1)
- Live AR try-on via ARKit (image-based VTO is enough)
- Collaboration (multiple designers editing same design simultaneously)
- Comments / annotations on shared designs from customers' devices
