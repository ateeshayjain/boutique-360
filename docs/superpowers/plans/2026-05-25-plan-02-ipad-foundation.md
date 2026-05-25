# Plan 2 — iPad App Foundation

**Goal:** A "Boutique 360" iPad app that builds, runs in the simulator, signs you in via Supabase magic-link, and shows a sidebar shell with Dashboard + Settings stubs.

**Stack:** Xcode 26+, iOS 17+ target, SwiftUI App lifecycle, Supabase Swift SDK (SwiftPM), XcodeGen for project file generation, Keychain for session persistence.

**Surface:** `ipad/` subdirectory inside the boutique-360 repo. Single Xcode project named `Boutique360.xcodeproj`.

**Spec:** `docs/superpowers/specs/2026-05-25-boutique-360-ipad-addendum.md`
**Prior plan:** Plan 1 (Backend Foundation) — Supabase project live at `tdnwdlrkbrtoxjzcgusg`

## File Structure

```
ipad/
├── project.yml                          # XcodeGen spec
├── Boutique360/
│   ├── Boutique360App.swift             # @main entry point
│   ├── Info.plist                       # CFBundle, URL schemes, universal links
│   ├── Boutique360.entitlements         # Associated Domains for universal links
│   ├── Configuration/
│   │   ├── Config.swift                 # reads Info.plist for Supabase URL/keys
│   │   └── Env.xcconfig                 # ENV-injected at build time (gitignored if secrets)
│   ├── Services/
│   │   ├── SupabaseService.swift        # singleton client wrapper
│   │   ├── AuthService.swift            # sign in/out, session refresh
│   │   └── KeychainStore.swift          # session token persistence
│   ├── Models/
│   │   └── Boutique.swift               # codable matching DB row
│   ├── Features/
│   │   ├── Auth/
│   │   │   ├── SignInView.swift         # email entry → magic link
│   │   │   └── AuthCallbackHandler.swift # processes universal link
│   │   ├── Root/
│   │   │   └── RootView.swift           # auth-gated split between SignIn and AppShell
│   │   ├── Shell/
│   │   │   └── AppShellView.swift       # NavigationSplitView (sidebar)
│   │   ├── Dashboard/
│   │   │   └── DashboardView.swift      # stub
│   │   └── Settings/
│   │       └── SettingsView.swift       # stub (boutique info + sign-out)
│   └── Assets.xcassets/
│       ├── AppIcon.appiconset/
│       └── AccentColor.colorset/
├── Boutique360Tests/
│   └── ConfigTests.swift                # smoke: Config loads
└── .gitignore                           # xcuserdata, DerivedData
```

**Naming:** lowercase `ipad/` directory (matches existing repo style); CamelCase Swift app target `Boutique360`. Bundle ID: `com.boutique360.designer.ipad`.

## Chunks

### Chunk 1: Project scaffold

#### Task 2.1 — Set up ipad/ directory + XcodeGen spec
- [ ] `mkdir -p ipad/Boutique360/{Configuration,Services,Models,Features/{Auth,Root,Shell,Dashboard,Settings},Assets.xcassets}`
- [ ] `mkdir -p ipad/Boutique360Tests`
- [ ] Write `ipad/project.yml`:

```yaml
name: Boutique360
options:
  deploymentTarget:
    iOS: "17.0"
  developmentLanguage: en
  bundleIdPrefix: com.boutique360.designer
  generateEmptyDirectories: true
settings:
  base:
    SWIFT_VERSION: "5.10"
    DEVELOPMENT_TEAM: ""           # set after Apple Developer enrollment
    TARGETED_DEVICE_FAMILY: "2"    # iPad only
    SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: "NO"
    ENABLE_USER_SCRIPT_SANDBOXING: "YES"
packages:
  Supabase:
    url: https://github.com/supabase/supabase-swift
    from: "2.20.0"
targets:
  Boutique360:
    type: application
    platform: iOS
    sources: [Boutique360]
    resources: [Boutique360/Assets.xcassets]
    settings:
      base:
        INFOPLIST_FILE: Boutique360/Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: com.boutique360.designer.ipad
        CODE_SIGN_ENTITLEMENTS: Boutique360/Boutique360.entitlements
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
    dependencies:
      - package: Supabase
        product: Supabase
  Boutique360Tests:
    type: bundle.unit-test
    platform: iOS
    sources: [Boutique360Tests]
    dependencies:
      - target: Boutique360
```

- [ ] `cd ipad && xcodegen generate` — verify `Boutique360.xcodeproj` created
- [ ] Commit

#### Task 2.2 — Info.plist + Entitlements + AccentColor + AppIcon stub
- [ ] Write `ipad/Boutique360/Info.plist` (minimal): name, version, supports iPad landscape+portrait, URL scheme `boutique360` for OAuth fallback, `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription` (needed later for fabric capture / VTO)
- [ ] Write `ipad/Boutique360/Boutique360.entitlements`: `com.apple.developer.associated-domains = ["applinks:app.boutique360.com"]` (universal link domain)
- [ ] Add `AccentColor.colorset/Contents.json` with brand color `#7C2D3C`
- [ ] Add `AppIcon.appiconset/Contents.json` (placeholder, real icons later)
- [ ] Commit

### Chunk 2: Config + Supabase client + Keychain

#### Task 2.3 — Configuration plumbing
- [ ] Create `Configuration/Env.xcconfig` with `SUPABASE_URL` and `SUPABASE_ANON_KEY` placeholders
- [ ] Reference in `project.yml` configFiles, regenerate project
- [ ] Update `Info.plist` to include `SUPABASE_URL = $(SUPABASE_URL)` and `SUPABASE_ANON_KEY = $(SUPABASE_ANON_KEY)`
- [ ] Write `Configuration/Config.swift`: read from Bundle.main.infoDictionary, fatal-error on missing
- [ ] Test: `Boutique360Tests/ConfigTests.swift` — reads real values
- [ ] Commit

#### Task 2.4 — Keychain wrapper
- [ ] Write `Services/KeychainStore.swift`: `save(key:value:)`, `load(key:)`, `delete(key:)` using `Security` framework
- [ ] Commit

#### Task 2.5 — Supabase client singleton
- [ ] Write `Services/SupabaseService.swift`: lazy singleton `SupabaseClient(supabaseURL:supabaseKey:)` using Config
- [ ] Expose `client.auth`, `client.from(...)`, `client.storage`
- [ ] Commit

### Chunk 3: Auth flow

#### Task 2.6 — AuthService
- [ ] Write `Services/AuthService.swift`: ObservableObject with `@Published var session: Session?`, methods `signInWithMagicLink(email:)`, `signOut()`, `handleAuthCallback(url:)`
- [ ] On init: try restore from Keychain → set session
- [ ] Commit

#### Task 2.7 — Sign-in view
- [ ] Write `Features/Auth/SignInView.swift`: email field, "Send magic link" button, success state
- [ ] Use `@EnvironmentObject AuthService`
- [ ] Commit

#### Task 2.8 — Universal link handler
- [ ] Write `Features/Auth/AuthCallbackHandler.swift`: parses `https://app.boutique360.com/auth/callback?code=...`, calls `AuthService.handleAuthCallback`
- [ ] Wire into `Boutique360App.swift` via `.onOpenURL`
- [ ] Document: Universal Link setup requires hosting `apple-app-site-association` at `https://app.boutique360.com/.well-known/apple-app-site-association` — this is web admin work (Plan 7); for now, deep-link via custom URL scheme `boutique360://auth/callback?...` works in simulator
- [ ] Commit

### Chunk 4: Shell + first views

#### Task 2.9 — Root view (auth gate)
- [ ] Write `Features/Root/RootView.swift`: if `authService.session == nil` → `SignInView`, else `AppShellView`
- [ ] Commit

#### Task 2.10 — App shell (NavigationSplitView)
- [ ] Write `Features/Shell/AppShellView.swift`: `NavigationSplitView` with sidebar items: Dashboard, Designs (stub), Customers (stub), Fabrics (stub), Catalog (stub), Settings
- [ ] Each sidebar item navigates to a view; only Dashboard + Settings have real views in this plan
- [ ] Commit

#### Task 2.11 — Dashboard stub
- [ ] Write `Features/Dashboard/DashboardView.swift`: fetches boutique row, displays name + tier counts as proof of end-to-end query
- [ ] Commit

#### Task 2.12 — Settings stub + sign-out
- [ ] Write `Features/Settings/SettingsView.swift`: shows current user email, boutique name, Sign Out button
- [ ] Commit

#### Task 2.13 — App entry point wires everything
- [ ] Write `Boutique360App.swift`: `@StateObject` AuthService, environmentObject down the tree, `RootView`
- [ ] Commit

### Chunk 5: Build + run

#### Task 2.14 — Build for iPad Pro 13" simulator
- [ ] `xcodebuild -project ipad/Boutique360.xcodeproj -scheme Boutique360 -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M5)" build`
- [ ] Fix any build errors
- [ ] Commit

#### Task 2.15 — Boot simulator + launch app
- [ ] `xcrun simctl boot "iPad Pro 13-inch (M5)"`
- [ ] `xcrun simctl install booted <built .app path>`
- [ ] `xcrun simctl launch booted com.boutique360.designer.ipad`
- [ ] Screenshot via `xcrun simctl io booted screenshot screenshot.png`
- [ ] Commit screenshot

### Verification checklist
- [ ] App builds with zero errors / warnings
- [ ] Launches in iPad Pro 13" simulator without crash
- [ ] Sign-in view renders, accepts email, shows "Check your email" state
- [ ] After paste-in of a real magic-link URL (since simulator can't receive APNs easily), session persists in Keychain
- [ ] Dashboard fetches and displays boutique name "Aditi Designer Studio"
- [ ] Sign-out clears session and returns to Sign-in

When done: **Plan 3 (iPad Design Canvas — PencilKit) is unblocked.**
