import SwiftUI

struct InquiriesListView: View {
    @State private var inquiries: [Inquiry] = []
    @State private var customers: [UUID: Customer] = [:]
    @State private var loading = false
    @State private var loadError: String?

    var body: some View {
        Group {
            if let err = loadError, inquiries.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't load inquiries", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(err)
                } actions: {
                    Button("Retry") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
            } else if inquiries.isEmpty && !loading {
                ContentUnavailableView(
                    "No inquiries yet",
                    systemImage: "envelope.badge",
                    description: Text("Inquiries appear here as customers reach out or you create them from a customer profile.")
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(InquiryStatus.kanbanColumns) { status in
                            column(for: status)
                        }
                    }
                    .padding(20)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .navigationTitle("Inquiries")
        .task { await load() }
        .refreshable { await load() }
    }

    private func column(for status: InquiryStatus) -> some View {
        let items = inquiries.filter { $0.status == status }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(status.label).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(items.count)").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            if items.isEmpty {
                Text("—").font(.caption).foregroundStyle(.tertiary).padding(8)
            } else {
                ForEach(items) { inq in
                    inquiryCard(inq)
                }
            }
        }
        .frame(width: 240, alignment: .topLeading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func inquiryCard(_ inq: Inquiry) -> some View {
        let customerName = customers[inq.customerId]?.name ?? "Loading…"
        return VStack(alignment: .leading, spacing: 6) {
            Text(customerName).font(.subheadline.weight(.medium)).lineLimit(1)
            Text(inq.inquiryNumber).font(.caption2).foregroundStyle(.secondary)
            if let o = inq.occasion { Text(o).font(.caption).lineLimit(2) }
            if let d = inq.eventDate { Label(d, systemImage: "calendar").font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            let inqs = try await InquiriesService.list()
            self.inquiries = inqs
            // batch-load customer names
            let ids = Set(inqs.map(\.customerId))
            let custs = try await CustomersService.list()
            self.customers = Dictionary(uniqueKeysWithValues: custs.filter { ids.contains($0.id) }.map { ($0.id, $0) })
            self.loadError = nil
        } catch {
            self.loadError = error.localizedDescription
        }
    }
}
