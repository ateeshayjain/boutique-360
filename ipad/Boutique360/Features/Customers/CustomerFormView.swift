import SwiftUI

struct CustomerFormView: View {
    enum Mode { case create, edit(Customer) }

    let mode: Mode
    let onSaved: (Customer) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ctx: BoutiqueContext

    @State private var name: String = ""
    @State private var phone: String = ""
    @State private var email: String = ""
    @State private var dob: Date = Date()
    @State private var hasDob: Bool = false
    @State private var vip: Bool = false
    @State private var consentWA: Bool = true
    @State private var consentEmail: Bool = false
    @State private var tagsRaw: String = ""
    @State private var source: String = "walkin"
    @State private var saving: Bool = false
    @State private var saveError: String?

    var body: some View {
        Form {
            Section("Contact") {
                TextField("Name", text: $name)
                    .textContentType(.name)
                TextField("Phone", text: $phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
            }

            Section("About") {
                Toggle("Capture birthday", isOn: $hasDob)
                if hasDob {
                    DatePicker("Birthday", selection: $dob, displayedComponents: .date)
                }
                Toggle("VIP", isOn: $vip)
                TextField("Tags (comma separated)", text: $tagsRaw)
                    .autocorrectionDisabled()
                Picker("Source", selection: $source) {
                    ForEach(["walkin","website","referral","instagram","ipad"], id: \.self) { Text($0.capitalized).tag($0) }
                }
            }

            Section("Consent (DPDP)") {
                Toggle("WhatsApp messages", isOn: $consentWA)
                Toggle("Email", isOn: $consentEmail)
                Text("Consent is required by DPDP Act for marketing & transactional messages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let err = saveError {
                Section { Text(err).foregroundStyle(.red).font(.caption) }
            }
        }
        .navigationTitle(isEditing ? "Edit customer" : "New customer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(saving ? "Saving…" : "Save") { Task { await save() } }
                    .disabled(saving || name.isEmpty || ctx.boutiqueId == nil)
            }
        }
        .onAppear { hydrate() }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true } else { return false }
    }

    private func hydrate() {
        if case .edit(let c) = mode {
            name = c.name
            phone = c.phone ?? ""
            email = c.email ?? ""
            vip = c.vipStatus
            consentWA = c.consentWhatsapp
            consentEmail = c.consentEmail
            source = c.source
            tagsRaw = c.tags.joined(separator: ", ")
            if let d = c.dob {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                if let parsed = f.date(from: d) { dob = parsed; hasDob = true }
            }
        }
    }

    private func save() async {
        guard let bid = ctx.boutiqueId else {
            saveError = "Boutique context unavailable"
            return
        }
        saving = true
        defer { saving = false }
        let tags = tagsRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let dobString: String? = {
            guard hasDob else { return nil }
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            return f.string(from: dob)
        }()

        do {
            switch mode {
            case .create:
                let input = NewCustomer(
                    boutique_id: bid, name: name,
                    phone: phone.isEmpty ? nil : phone,
                    email: email.isEmpty ? nil : email,
                    dob: dobString,
                    tags: tags,
                    vip_status: vip,
                    source: source,
                    consent_whatsapp: consentWA,
                    consent_email: consentEmail
                )
                let created = try await CustomersService.create(input)
                onSaved(created)
                dismiss()
            case .edit(let c):
                let patch = CustomersService.CustomerPatch(
                    name: name,
                    phone: phone.isEmpty ? nil : phone,
                    email: email.isEmpty ? nil : email,
                    dob: dobString,
                    vip_status: vip,
                    consent_whatsapp: consentWA,
                    consent_email: consentEmail,
                    source: source,
                    tags: tags
                )
                let updated = try await CustomersService.update(c.id, patch: patch)
                onSaved(updated)
                dismiss()
            }
        } catch {
            saveError = error.localizedDescription
        }
    }
}
