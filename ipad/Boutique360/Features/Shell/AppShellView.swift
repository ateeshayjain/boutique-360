import SwiftUI

enum SidebarSection: String, Hashable, CaseIterable, Identifiable {
    case dashboard, calendar, designs, customers, inquiries, orders, dates, fabrics, catalog, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .calendar:  "Calendar"
        case .designs:   "Designs"
        case .customers: "Customers"
        case .inquiries: "Inquiries"
        case .orders:    "Orders"
        case .dates:     "Important dates"
        case .fabrics:   "Fabrics"
        case .catalog:   "Catalog"
        case .settings:  "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "rectangle.grid.2x2"
        case .calendar:  "calendar"
        case .designs:   "pencil.and.scribble"
        case .customers: "person.2"
        case .inquiries: "envelope.open"
        case .orders:    "bag"
        case .dates:     "gift"
        case .fabrics:   "square.grid.3x3.square"
        case .catalog:   "tag"
        case .settings:  "gearshape"
        }
    }
}

struct AppShellView: View {
    @EnvironmentObject private var roles: StaffRoleContext
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
            // R4b — the active role must never be ambiguous (Apple Design
            // Principle 1). It lives in the sidebar rather than a detail
            // toolbar so it survives every navigation push, and it only
            // appears in assistant mode: owner is the resting state and a
            // permanent "Owner" chip would just become invisible.
            .safeAreaInset(edge: .bottom) {
                if roles.role == .assistant {
                    Button {
                        selection = .settings
                    } label: {
                        Label("Assistant mode", systemImage: "person.badge.shield.checkmark")
                            .font(.footnote.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: CornerRadius.chip))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                    .padding(Spacing.medium)
                    .accessibilityHint("Payments and invoices are hidden. Opens Settings to unlock as owner.")
                }
            }
        } detail: {
            NavigationStack {
                switch selection {
                case .dashboard:  DashboardView()
                case .calendar:   CalendarView()
                case .customers:  CustomersListView()
                case .inquiries:  InquiriesListView()
                case .orders:     OrdersListView()
                case .dates:      ImportantDatesListView()
                case .designs:    DesignsListView()
                case .fabrics:    ComingSoonView(title: "Fabrics",   subtitle: "Coming with Workshop OS")
                case .catalog:    ComingSoonView(title: "Catalog",   subtitle: "For ready-to-ship lookbook")
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
