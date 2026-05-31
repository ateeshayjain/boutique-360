import SwiftUI

/// Lightweight non-blocking error toast pipeline. The silent-failure-hunter
/// agent recommended a central error sink as the systemic fix for the 50+
/// `try? await` patterns. This is the minimum-viable version: any service or
/// view can call `ErrorBus.shared.report("...")` and the RootView shows a
/// transient toast.
///
/// Not a full Combine subject because SwiftUI's `.onReceive` is the ergonomic
/// subscriber, and we don't need replay semantics.
@MainActor
final class ErrorBus: ObservableObject {
    static let shared = ErrorBus()

    @Published var current: Toast?

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let isError: Bool
    }

    func report(_ message: String, isError: Bool = true) {
        current = Toast(message: message, isError: isError)
        // Auto-dismiss so toasts don't pile up. 4s is enough to read.
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if current?.message == message { current = nil }
        }
    }

    private init() {}
}

/// Modifier you can attach to RootView so toasts overlay the entire app.
struct ErrorToastOverlay: ViewModifier {
    @ObservedObject private var bus = ErrorBus.shared
    // HIG audit fix (Principle 6 — accessibility): respect Reduce Motion.
    // When the system setting is on, swap the slide+fade for an opacity-only
    // transition so motion-sensitive users aren't jarred.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast = bus.current {
                HStack(spacing: Spacing.small + 2) {
                    Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .foregroundStyle(toast.isError ? .orange : .blue)
                        .accessibilityHidden(true)
                    Text(toast.message).font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button {
                        bus.current = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Dismiss")
                }
                .padding(Spacing.medium - 4)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card))
                .shadow(radius: Spacing.small)
                .padding(.horizontal, Spacing.large)
                .padding(.bottom, Spacing.large)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .animation(.easeOut(duration: AnimationToken.standard), value: toast.id)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

extension View {
    func errorToastOverlay() -> some View { modifier(ErrorToastOverlay()) }
}
