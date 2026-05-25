import SwiftUI

enum SidebarSection: String, Hashable, CaseIterable, Identifiable {
    case dashboard, designs, customers, fabrics, catalog, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .designs:   "Designs"
        case .customers: "Customers"
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
        case .fabrics:   "square.grid.3x3.square"
        case .catalog:   "tag"
        case .settings:  "gearshape"
        }
    }
}

struct AppShellView: View {
    @State private var selection: SidebarSection? = .dashboard

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
                case .designs:    ComingSoonView(title: "Designs",   subtitle: "Plan 3 — PencilKit canvas")
                case .customers:  ComingSoonView(title: "Customers", subtitle: "Plan 5")
                case .fabrics:    ComingSoonView(title: "Fabrics",   subtitle: "Plan 3")
                case .catalog:    ComingSoonView(title: "Catalog",   subtitle: "Plan 5")
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
