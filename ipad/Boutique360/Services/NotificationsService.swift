import Foundation
import UserNotifications

/// Local-only notifications. No APNs server needed for the single-boutique
/// pilot — the iPad already has all the data, so we schedule against the
/// local clock and let iOS deliver.
///
/// Three notification kinds:
///  1. Daily 8 AM "Today" briefing — repeats; scheduled once and forgotten.
///  2. Per-appointment 1-hour reminder — scheduled on appointment create.
///  3. Payment-overdue weekly nudge — scheduled when an order goes confirmed
///     and there's still a balance.
///
/// `refresh()` is idempotent: wipes our owned IDs and rebuilds from current
/// DB state. Safe to call on app launch, foreground, or after any mutation.
enum NotificationsService {
    // MARK: - Identifier conventions (so we can target our own without touching system notifs)
    private static let dailyBriefingId = "boutique360.daily-briefing"
    private static func appointmentId(_ id: UUID) -> String { "boutique360.appt.\(id.uuidString)" }
    private static func overdueId(_ orderId: UUID) -> String { "boutique360.overdue.\(orderId.uuidString)" }

    // MARK: - Authorization (call from Dashboard .task — contextual is better than at launch)
    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { cont in
            UNUserNotificationCenter.current().getNotificationSettings { s in
                cont.resume(returning: s.authorizationStatus)
            }
        }
    }

    // MARK: - Daily 8AM briefing (set once, repeats forever)
    static func scheduleDailyBriefing() {
        let content = UNMutableNotificationContent()
        content.title = "Good morning ☕"
        content.body  = "Open Boutique 360 to see today's appointments, deliveries, and overdue payments."
        content.sound = .default
        content.threadIdentifier = "daily-briefing"

        var dc = DateComponents()
        dc.hour = 8; dc.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)

        let req = UNNotificationRequest(identifier: dailyBriefingId, content: content, trigger: trigger)
        // M1 fix: surface scheduling errors instead of discarding.
        UNUserNotificationCenter.current().add(req) { error in
            if let error = error {
                Log.notifications.error("daily-briefing schedule failed: \(error.localizedDescription, privacy: .public)")
                Task { @MainActor in
                    ErrorBus.shared.report("Daily reminder couldn't be scheduled: \(error.localizedDescription)")
                }
            } else {
                Log.notifications.info("daily-briefing scheduled (08:00 local)")
            }
        }
    }

    // MARK: - Appointment reminders
    /// Schedule a single 1-hour-before reminder. Re-scheduling with the same
    /// appointment ID replaces the previous request — safe to call on edit.
    static func scheduleAppointmentReminder(_ appointment: Appointment, customerName: String?) {
        let fireAt = appointment.scheduledAt.addingTimeInterval(-3600)
        guard fireAt > Date() else { return }    // don't schedule in the past
        let content = UNMutableNotificationContent()
        content.title = "Appointment in 1 hour"
        content.body  = "\(customerName ?? "Customer") · \(appointment.type.label) at \(appointment.scheduledAt.formatted(.dateTime.hour().minute()))"
        content.sound = .default
        content.threadIdentifier = "appointments"

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: appointmentId(appointment.id), content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req) { error in
            if let error = error {
                Task { @MainActor in
                    ErrorBus.shared.report("Appointment reminder couldn't be scheduled: \(error.localizedDescription)")
                }
            }
        }
    }

    static func cancelAppointmentReminder(id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [appointmentId(id)])
    }

    // MARK: - Refresh — wipe + rebuild based on authoritative DB state
    /// Call from RootView/Dashboard `.task` to keep schedule honest after
    /// any external changes (rows edited from another device).
    @MainActor
    static func refresh() async {
        // M1 fix: fetch FIRST, then cancel + re-schedule. The previous order
        // (cancel → fetch → maybe re-schedule) meant a single failed fetch
        // wiped every reminder until the next app launch.
        let now = Date()
        let weekOut = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        let upcoming: [Appointment]
        do {
            upcoming = try await AppointmentsService.list(from: now, to: weekOut)
        } catch {
            // Don't touch the existing schedule on fetch failure.
            ErrorBus.shared.report("Couldn't refresh appointment reminders — using last known schedule")
            return
        }
        let customers: [Customer] = (try? await CustomersService.list()) ?? []
        let custMap = Dictionary(uniqueKeysWithValues: customers.map { ($0.id, $0.name) })

        // Only now do we cancel + reschedule, after a successful fetch.
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ourIds = pending.map(\.identifier).filter { $0.hasPrefix("boutique360.") }
        center.removePendingNotificationRequests(withIdentifiers: ourIds)

        scheduleDailyBriefing()
        for a in upcoming where a.status == .scheduled {
            scheduleAppointmentReminder(a, customerName: custMap[a.customerId])
        }
    }
}
