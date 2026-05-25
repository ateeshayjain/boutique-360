import SwiftUI

struct DashboardView: View {
    @State private var boutique: Boutique?
    @State private var tiers: [LoyaltyTier] = []
    @State private var loadError: String?
    @State private var loading: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                tierStrip
                placeholderStats
            }
            .padding(32)
        }
        .navigationTitle("Dashboard")
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if loading {
                ProgressView()
            } else if let err = loadError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            } else if let b = boutique {
                Text(b.name)
                    .font(.system(size: 36, weight: .semibold, design: .serif))
                if let gstin = b.gstin {
                    Text("GSTIN \(gstin)").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Boutique 360").font(.system(size: 36, weight: .semibold, design: .serif))
            }
        }
    }

    private var tierStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Loyalty tiers").font(.headline)
            HStack(spacing: 12) {
                ForEach(tiers) { tier in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: tier.colorHex ?? "#888888"))
                            .frame(width: 12, height: 12)
                        Text(tier.name).font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
                }
            }
        }
    }

    private var placeholderStats: some View {
        LazyVGrid(columns: [.init(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
            ForEach(["Today's orders", "Active inquiries", "Designs in progress", "Messages awaiting reply"], id: \.self) { label in
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    Text("—").font(.system(size: 32, weight: .semibold))
                    Text("coming in Plan 5+").font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let b: [Boutique] = try await SupabaseService.client
                .from("boutiques")
                .select()
                .limit(1)
                .execute()
                .value
            self.boutique = b.first

            let t: [LoyaltyTier] = try await SupabaseService.client
                .from("loyalty_tiers")
                .select("id,name,color_hex,sort_order")
                .order("sort_order", ascending: true)
                .execute()
                .value
            self.tiers = t
            self.loadError = nil
        } catch {
            self.loadError = "Could not load boutique: \(error.localizedDescription)"
        }
    }
}

// MARK: - Color hex helper
extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8)  & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}
