import SwiftUI

/// R4a — auto-drafted reminders with one-tap approve. Pure renderer; the
/// drafts arrive pre-built from `ReminderDrafts` and pre-filtered for role.
///
/// Sending deliberately does NOT mark a draft done: the owner may edit or
/// cancel inside WhatsApp, so "Mark done" stays an explicit second act
/// (spec Unit 7).
struct RemindersSectionView: View {
    let drafts: [ReminderDrafts.Draft]
    let isLoading: Bool
    let onSend: (ReminderDrafts.Draft) -> Void
    let onMarkDone: (ReminderDrafts.Draft) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            GroupBox {
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Checking reminders…")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                } else if drafts.isEmpty {
                    Text("No reminders right now — fittings, balances, and ready orders will appear here.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 0) {
                        ForEach(drafts) { draft in
                            row(draft)
                            if draft.id != drafts.last?.id { Divider() }
                        }
                    }
                    Text("Sending opens WhatsApp — tap Mark done once you've sent it.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
            }
        }
    }

    private var header: some View {
        // Count comes from the rendered list, so it can never claim more
        // rows than are shown (e.g. after assistant-mode filtering).
        Label("Reminders\(isLoading || drafts.isEmpty ? "" : " · \(countText)")",
              systemImage: "bell.badge")
            .font(.headline)
    }

    /// Real plural forms — never "reminder(s)" (Content §5).
    private var countText: String {
        drafts.count == 1 ? "1 reminder" : "\(drafts.count) reminders"
    }

    private func row(_ draft: ReminderDrafts.Draft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon(for: draft.kind))
                    .foregroundStyle(tint(for: draft.kind))
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.customerName).font(.subheadline.weight(.medium))
                    if let context = contextLine(draft) {
                        Text(context).font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(draft.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            // ≥44pt targets with ≥8pt spacing (Apple Design §3.1). The
            // buttons wrap below the text rather than truncating at the
            // largest Dynamic Type sizes.
            HStack(spacing: 12) {
                Button {
                    onSend(draft)
                } label: {
                    Label("Send on WhatsApp", systemImage: "message.fill")
                        .font(.caption.weight(.medium))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(.green)

                Button {
                    onMarkDone(draft)
                } label: {
                    Label("Mark done", systemImage: "checkmark.circle")
                        .font(.caption.weight(.medium))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kindLabel(draft.kind)) reminder for \(draft.customerName). \(draft.message)")
    }

    private func contextLine(_ draft: ReminderDrafts.Draft) -> String? {
        var parts: [String] = []
        if let no = draft.orderNumber { parts.append(no) }
        if let due = draft.amountDue { parts.append(Formatters.inr(due)) }
        parts.append(kindLabel(draft.kind))
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func kindLabel(_ kind: ReminderDrafts.Kind) -> String {
        switch kind {
        case .fitting: "Fitting"
        case .payment: "Balance due"
        case .ready:   "Ready"
        }
    }
    private func icon(for kind: ReminderDrafts.Kind) -> String {
        switch kind {
        case .fitting: "ruler"
        case .payment: "indianrupeesign.circle"
        case .ready:   "checkmark.seal"
        }
    }
    private func tint(for kind: ReminderDrafts.Kind) -> Color {
        switch kind {
        case .fitting: .blue
        case .payment: .orange
        case .ready:   .green
        }
    }
}
