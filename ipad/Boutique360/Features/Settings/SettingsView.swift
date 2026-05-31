import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var ctx: BoutiqueContext
    @State private var confirmSignOut = false
    @State private var showEditBoutique = false

    // GST export state
    @State private var exportMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var exportYear: Int = Calendar.current.component(.year, from: Date())
    @State private var exportBundle: GSTReportExporter.Bundle?
    @State private var exporting = false
    @State private var showExportShare = false
    @State private var exportFileURL: URL?
    @State private var exportError: String?
    // M2 fix: compute month names once instead of per-render DateFormatter().monthSymbols.
    private let monthNames: [String] = Calendar(identifier: .gregorian).standaloneMonthSymbols

    // Customer import state
    @State private var showImporter = false
    @State private var importPreview: CustomerImportService.Report?
    @State private var importing = false
    @State private var importResult: CustomerImportService.Report?

    var body: some View {
        Form {
            Section {
                LabeledContent("Name", value: ctx.boutique?.name ?? "—")
                LabeledContent("GSTIN", value: ctx.boutique?.gstin ?? "—")
                LabeledContent("Place of supply", value: ctx.boutique?.placeOfSupply ?? "—")
                LabeledContent("Address", value: ctx.boutique?.address ?? "—")
                if ctx.boutique?.gstin == nil {
                    Label("GSTIN missing — invoices disabled.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                Button {
                    showEditBoutique = true
                } label: {
                    Label("Edit boutique details", systemImage: "pencil")
                }
            } header: { Text("Boutique") }
            Section("Account") {
                LabeledContent("Email", value: auth.session?.user.email ?? "—")
                LabeledContent("Role", value: ctx.staffRole?.capitalized ?? "—")
            }

            gstExportSection
            customerImportSection

            Section("App") {
                LabeledContent("Supabase URL", value: Config.supabaseURL.host ?? "—")
                LabeledContent("App version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            }
            Section {
                Button(role: .destructive) {
                    confirmSignOut = true
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Sign out of Boutique 360?",
            isPresented: $confirmSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) {
                Task { await auth.signOut() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You'll need your email to sign back in.")
        }
        .sheet(isPresented: $showEditBoutique) {
            NavigationStack {
                EditBoutiqueView()
            }
            .presentationDetents([.medium, .large])
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleImport(result: result) }
        }
    }

    // MARK: - GST export

    private var gstExportSection: some View {
        Section {
            HStack {
                Picker("Month", selection: $exportMonth) {
                    ForEach(1...12, id: \.self) { m in
                        Text(monthNames[m - 1]).tag(m)
                    }
                }
                .pickerStyle(.menu)
                Picker("Year", selection: $exportYear) {
                    let now = Calendar.current.component(.year, from: Date())
                    ForEach((now - 2)...now, id: \.self) { y in
                        Text(String(y)).tag(y)
                    }
                }
                .pickerStyle(.menu)
            }
            Button {
                Task { await runExport() }
            } label: {
                HStack {
                    Label(exporting ? "Generating…" : "Export GST CSV for filing", systemImage: "square.and.arrow.up.on.square")
                    Spacer()
                    if exporting { ProgressView() }
                }
            }
            .disabled(exporting || ctx.boutique == nil)

            if let err = exportError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.caption)
            }
            if let bundle = exportBundle {
                VStack(alignment: .leading, spacing: 4) {
                    // H1 fix: use Formatters.inr for lakh-style grouping (₹1,25,000 not ₹125000).
                    Text("\(bundle.rowCount) orders · taxable \(Formatters.inr(bundle.totalTaxable)) · GST \(Formatters.inr(bundle.totalTax))")
                        .font(.caption)
                    if bundle.interStateUnknown > 0 {
                        // H10 fix: warn the CA when shipped orders may be inter-state.
                        Label("\(bundle.interStateUnknown) shipped orders — spot-check whether IGST applies (delivered to another state).",
                              systemImage: "info.circle.fill")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                    if let url = exportFileURL {
                        ShareLink(item: url) {
                            Label("Share CSV (email to CA)", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        } header: {
            Text("GST report")
        } footer: {
            Text("Generates a CSV your chartered accountant can paste into the GSTR-1 portal. Assumes intra-state supply (CGST + SGST split).")
        }
    }

    // MARK: - Customer import

    private var customerImportSection: some View {
        Section {
            Button {
                showImporter = true
            } label: {
                Label("Import customers from CSV", systemImage: "square.and.arrow.down")
            }
            if let r = importResult {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Inserted \(r.inserted) of \(r.parsed.count) rows")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(r.inserted == r.parsed.count ? .green : .orange)
                    if !r.skipped.isEmpty {
                        Text("Skipped \(r.skipped.count) row(s) during parse").font(.caption2).foregroundStyle(.secondary)
                    }
                    if !r.failed.isEmpty {
                        Text("Failed \(r.failed.count) insert(s)").font(.caption2).foregroundStyle(.red)
                    }
                }
            }
        } header: {
            Text("Customer import")
        } footer: {
            Text("CSV requires a 'name' column. Optional: phone, email, tags (semicolon-separated), source, vip, whatsapp_consent, email_consent, dob.")
        }
    }

    // MARK: - Actions

    private func runExport() async {
        guard let b = ctx.boutique else { return }
        exporting = true; defer { exporting = false }
        do {
            // H11 fix: refuse to export on data-fetch failure (filing ₹0 turnover is a statutory offense).
            let bundle = try await GSTReportExporter.monthly(year: exportYear, month: exportMonth, boutique: b)
            exportBundle = bundle
            exportError = nil
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(bundle.filename)
            try? bundle.data.write(to: url)
            exportFileURL = url
        } catch {
            exportError = "Couldn't generate report: \(error.localizedDescription). Check network and retry."
            exportBundle = nil
            exportFileURL = nil
        }
    }

    private func handleImport(result: Result<[URL], Error>) async {
        guard let bid = ctx.boutiqueId else { return }
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importing = true; defer { importing = false }
            // Permission scope: needed for files outside our sandbox.
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else { return }
            let parsed = CustomerImportService.parse(csv: text)
            importPreview = parsed
            // For pilot simplicity, import immediately (no preview-confirm step).
            // Confirm-before-import can be added later when files have 100+ rows.
            importResult = await CustomerImportService.importRows(parsed.parsed, boutiqueId: bid)
        case .failure:
            break
        }
    }
}

/// Inline editor for the four most-edited boutique fields. Saves directly to
/// Supabase and asks BoutiqueContext to refresh so the rest of the app picks
/// up the change (invoices in particular depend on GSTIN/place_of_supply).
struct EditBoutiqueView: View {
    @EnvironmentObject private var ctx: BoutiqueContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var gstin = ""
    @State private var placeOfSupply = ""
    @State private var address = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Boutique name", text: $name)
                TextField("GSTIN (15 chars)", text: $gstin)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                // M10 fix: inline GSTIN structural validation at submit time.
                if let problem = GSTINValidator.problem(in: gstin) {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(.orange)
                }
                TextField("Place of supply (state)", text: $placeOfSupply)
            }
            Section("Address") {
                TextField("Full address (one line)", text: $address, axis: .vertical)
                    .lineLimit(2...4)
            }
            if let err = error {
                Section { Text(err).foregroundStyle(.red).font(.caption) }
            }
        }
        .navigationTitle("Edit boutique")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(saving ? "Saving…" : "Save") { Task { await save() } }
                    // Block save if GSTIN is structurally invalid; empty is OK.
                    .disabled(saving || !GSTINValidator.isValid(gstin))
            }
        }
        .onAppear {
            name = ctx.boutique?.name ?? ""
            gstin = ctx.boutique?.gstin ?? ""
            placeOfSupply = ctx.boutique?.placeOfSupply ?? ""
            address = ctx.boutique?.address ?? ""
        }
    }

    private func save() async {
        guard let bid = ctx.boutiqueId else { return }
        saving = true; defer { saving = false }
        let patch = BoutiqueService.Patch(
            name: name.trimmingCharacters(in: .whitespaces),
            gstin: gstin.trimmingCharacters(in: .whitespaces).isEmpty ? nil : gstin.trimmingCharacters(in: .whitespaces),
            place_of_supply: placeOfSupply.trimmingCharacters(in: .whitespaces).isEmpty ? nil : placeOfSupply,
            address: address.trimmingCharacters(in: .whitespaces).isEmpty ? nil : address
        )
        do {
            // Audit-fix: through Service layer.
            try await BoutiqueService.update(id: bid, patch: patch)
            await ctx.refresh()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
