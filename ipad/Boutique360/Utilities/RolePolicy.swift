import Foundation

/// R4b — which surfaces an assistant may not see.
///
/// This is a **same-device UI boundary, not server-side authorization**. The
/// app holds one Supabase account; anyone with the session token or the
/// Supabase dashboard reads everything regardless of role. Real RBAC needs
/// per-staff accounts with RLS on staff role — deferred, and named as the
/// mitigation in SECURITY_REVIEW.md. Enumerating surfaces here is what keeps
/// that boundary auditable.
enum RolePolicy {
    /// Every surface that shows money or configuration. Adding a case here
    /// fails `RolePolicyTests.testSurfaceCountIsPinned` until someone
    /// consciously reviews where it is enforced.
    enum Surface: String, CaseIterable {
        case payments             // PaymentsSectionView — the whole section
        case revenueTile          // DashboardView.todaysRevenueCard
        case moneyDueTile         // MorningBoardView money-due tile
        case spendPanel           // CustomerSpendSummaryView
        case invoice              // OrderDetailView invoice button + preview sheet
        case gstExport            // SettingsView.gstExportSection
        case razorpayLink         // PaymentsSectionView payment-link button
        case lockPricing          // LockSheet breakup/advance, LockSummarySheet money
        case settingsSensitive    // Settings integrations + boutique identity
        case paymentReminders     // payment drafts + paymentsOverdueSection + needs-you amounts
    }

    static func canSee(_ surface: Surface, role: StaffRole) -> Bool {
        role == .owner
    }
}
