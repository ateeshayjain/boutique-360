import SwiftUI

/// Day-by-day fittings + appointments calendar.
/// HIG: vertical list grouped by date sections — same pattern as Apple Calendar's day view.
struct CalendarView: View {
    @State private var appointments: [Appointment] = []
    @State private var customers: [UUID: Customer] = [:]
    @State private var selectedDate: Date = Date()
    @State private var showCreate = false
    @State private var loading = false

    var body: some View {
        VStack(spacing: 0) {
            DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding(.horizontal)
                .frame(maxHeight: 320)
                .onChange(of: selectedDate) { _, _ in Task { await load() } }

            Divider()

            Group {
                if loading {
                    ProgressView().frame(maxHeight: .infinity)
                } else if filteredForDay.isEmpty {
                    ContentUnavailableView(
                        "Nothing scheduled",
                        systemImage: "calendar.badge.checkmark",
                        description: Text("Tap + to schedule a fitting, consultation, or pickup.")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filteredForDay) { appt in
                            AppointmentRow(appt: appt, customerName: customers[appt.customerId]?.name ?? "—")
                                .swipeActions(edge: .trailing) {
                                    Button("Done") {
                                        Task {
                                            _ = try? await AppointmentsService.updateStatus(appt.id, to: .completed)
                                            await load()
                                        }
                                    }
                                    .tint(.green)
                                    Button("Cancel", role: .destructive) {
                                        Task {
                                            _ = try? await AppointmentsService.updateStatus(appt.id, to: .cancelled)
                                            await load()
                                        }
                                    }
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
        }
        .navigationTitle("Calendar")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showCreate = true } label: { Label("New", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                AppointmentFormView(initialDate: selectedDate) {
                    showCreate = false
                    Task { await load() }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var filteredForDay: [Appointment] {
        let cal = Calendar.current
        return appointments.filter { cal.isDate($0.scheduledAt, inSameDayAs: selectedDate) }
    }

    private func load() async {
        loading = true; defer { loading = false }
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: selectedDate))!
        let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart)!
        do {
            appointments = try await AppointmentsService.list(from: monthStart, to: monthEnd)
            let custIds = Set(appointments.map(\.customerId))
            if !custIds.isEmpty {
                let all = (try? await CustomersService.list()) ?? []
                customers = Dictionary(uniqueKeysWithValues: all.filter { custIds.contains($0.id) }.map { ($0.id, $0) })
            }
        } catch { /* silent — empty state shown */ }
    }
}

private struct AppointmentRow: View {
    let appt: Appointment
    let customerName: String

    var body: some View {
        HStack(spacing: 12) {
            VStack {
                Text(appt.scheduledAt.formatted(.dateTime.hour().minute()))
                    .font(.subheadline.weight(.medium)).monospacedDigit()
                Text("\(appt.durationMinutes)m")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 60)

            Divider()

            Image(systemName: appt.type.systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(customerName).font(.body.weight(.medium))
                Text(appt.type.label).font(.caption).foregroundStyle(.secondary)
                if let n = appt.notes, !n.isEmpty {
                    Text(n).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer()

            if appt.status != .scheduled {
                Text(appt.status.label).font(.caption2)
                    .foregroundStyle(appt.status == .completed ? .green : .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
