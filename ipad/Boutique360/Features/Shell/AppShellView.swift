import SwiftUI

enum SidebarSection: String, Hashable, CaseIterable, Identifiable {
    case dashboard, designs, customers, inquiries, fabrics, catalog, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .designs:   "Designs"
        case .customers: "Customers"
        case .inquiries: "Inquiries"
        case .fabrics:   "Fabrics"
        case .catalog:   "Catalog"
        case .settings:  "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "rectangle.grid.2x2"
        case .designs:   "pencil.and.scribble"
        case .customers: "person.2"
        case .inquiries: "envelope.open"
        case .fabrics:   "square.grid.3x3.square"
        case .catalog:   "tag"
        case .settings:  "gearshape"
        }
    }
}

struct AppShellView: View {
    @State private var selection: SidebarSection? = {
        // DEV: -start-section <name> overrides default landing tab
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-start-section"), i + 1 < args.count,
           let s = SidebarSection(rawValue: args[i + 1]) {
            return s
        }
        return .dashboard
    }()

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("Boutique 360")
            .listStyle(.sidebar)
        } detail: {
            NavigationStack {
                switch selection {
                case .dashboard:  DashboardView()
                case .customers:  CustomersListView()
                case .inquiries:  InquiriesListView()
                case .designs:    ComingSoonView(title: "Designs",   subtitle: "Plan 4 — PencilKit canvas")
                case .fabrics:    ComingSoonView(title: "Fabrics",   subtitle: "Plan 4")
                case .catalog:    ComingSoonView(title: "Catalog",   subtitle: "Plan 6")
                case .settings:   SettingsView()
                case .none:       DashboardView()
                }
            }
        }
    }
}

private struct ComingSoonView: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hourglass")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.title2.weight(.medium))
            Text(subtitle).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(title)
    }
}
