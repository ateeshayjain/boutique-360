import SwiftUI

struct CustomerFormView: View {
    enum Mode { case create, edit(Customer) }

    let mode: Mode
    let onSaved: (Customer) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ctx: BoutiqueContext

    @State private var name: String = ""
    @State private var phone: String = ""
    @State private var whatsappPhone: String = ""
    @State private var sameAsPhone: Bool = true
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

    // Wave 1: address fields. Each is bound to a String; we materialize an
    // Address only when at least one is non-empty (so brand-new customers
    // don't round-trip an empty address_json blob through the DB).
    @State private var addrLine1: String = ""
    @State private var addrLine2: String = ""
    @State private var addrCity: String = ""
    @State private var addrState: String = ""
    @State private var addrPin: String = ""
    @State private var addrCountry: String = "India"

    var body: some View {
        Form {
            Section("Contact") {
                TextField("Name", text: $name)
                    .textContentType(.name)
                TextField("Phone (billing)", text: $phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                Toggle("WhatsApp is same as phone", isOn: $sameAsPhone)
                if !sameAsPhone {
                    TextField("WhatsApp number", text: $whatsappPhone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                }
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
            }

            Section("Address") {
                TextField("Line 1 (house, street)", text: $addrLine1)
                    .textContentType(.streetAddressLine1)
                TextField("Line 2 (area, landmark)", text: $addrLine2)
                    .textContentType(.streetAddressLine2)
                TextField("City", text: $addrCity)
                    .textContentType(.addressCity)
                TextField("State", text: $addrState)
                    .textContentType(.addressState)
                TextField("PIN", text: $addrPin)
                    .textContentType(.postalCode)
                    .keyboardType(.numberPad)
                TextField("Country", text: $addrCountry)
                    .textContentType(.countryName)
                Text("Used on invoices and shipping. Leave blank if not relevant.")
                    .font(.caption2).foregroundStyle(.secondary)
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
            whatsappPhone = c.whatsappPhone ?? ""
            // "same as phone" is true when whatsappPhone is unset OR matches phone.
            sameAsPhone = (c.whatsappPhone?.isEmpty ?? true) || c.whatsappPhone == c.phone
            email = c.email ?? ""
            vip = c.vipStatus
            consentWA = c.consentWhatsapp
            consentEmail = c.consentEmail
            source = c.source
            tagsRaw = c.tags.joined(separator: ", ")
            if let d = c.dob,
               let parsed = Formatters.postgresDate.date(from: d) {
                dob = parsed; hasDob = true
            }
            if let a = c.address {
                addrLine1 = a.line1 ?? ""
                addrLine2 = a.line2 ?? ""
                addrCity = a.city ?? ""
                addrState = a.state ?? ""
                addrPin = a.pin ?? ""
                addrCountry = a.country ?? "India"
            }
        }
    }

    /// Build an `Address?` from the form. Returns nil iff every field is
    /// blank — that way we don't persist `address_json = {}` for users who
    /// skipped the section.
    private func buildAddress() -> Address? {
        let a = Address(
            line1: addrLine1.trimmingCharacters(in: .whitespaces).nonEmpty,
            line2: addrLine2.trimmingCharacters(in: .whitespaces).nonEmpty,
            city: addrCity.trimmingCharacters(in: .whitespaces).nonEmpty,
            state: addrState.trimmingCharacters(in: .whitespaces).nonEmpty,
            pin: addrPin.trimmingCharacters(in: .whitespaces).nonEmpty,
            country: addrCountry.trimmingCharacters(in: .whitespaces).nonEmpty
        )
        return a.isEmpty ? nil : a
    }

    /// Resolve WA #: if "same as phone" or the WA field is blank, return nil
    /// (server stores nil; reads fall back to `phone` via `whatsappTarget`).
    private func resolvedWhatsappPhone() -> String? {
        if sameAsPhone { return nil }
        let trimmed = whatsappPhone.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
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
            return Formatters.postgresDate.string(from: dob)
        }()
        let address = buildAddress()
        let waPhone = resolvedWhatsappPhone()

        do {
            switch mode {
            case .create:
                let input = NewCustomer(
                    boutique_id: bid, name: name,
                    phone: phone.isEmpty ? nil : phone,
                    whatsapp_phone: waPhone,
                    email: email.isEmpty ? nil : email,
                    dob: dobString,
                    address_json: address,
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
                    whatsapp_phone: waPhone,
                    email: email.isEmpty ? nil : email,
                    dob: dobString,
                    address_json: address,
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

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
