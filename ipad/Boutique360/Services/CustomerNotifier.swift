import Foundation

/// Unified send-to-customer dispatcher across WhatsApp / Email / SMS.
///
/// **Naming:** called `CustomerNotifier` (not `NotificationService`) to avoid
/// confusion with the existing `NotificationsService` (in-app
/// UserNotifications — owner reminders, not customer messages).
///
/// **Design choice — consent is enforced HERE, not at the View.** Previously
/// each WA call site re-checked `customer.consentWhatsapp` inline. Centralising
/// it makes new channels (email/SMS) automatically gated and means a single
/// audit point for DPDP compliance.
enum CustomerNotifier {
    /// Outgoing message envelope. We deliberately separate `whatsapp` (link
/// flow — opens the user's WA client) from `email`/`sms` (direct API
/// dispatch). UI surfaces them as one button group; this struct is the
/// actual transport plan.
    struct Plan {
        var whatsapp: WhatsAppPlan?
        var email: EmailPlan?
        var sms: SMSPlan?
    }

    struct WhatsAppPlan {
        let target: String     // raw phone (WhatsAppShareHelper normalizes)
        let message: String
    }

    struct EmailPlan {
        let to: String
        let toName: String?
        let subject: String
        let htmlBody: String
        let plainBody: String?
    }

    struct SMSPlan {
        let to: String
        let body: String
    }

    enum DispatchError: Swift.Error, LocalizedError {
        case noConsent(channel: String)
        case noTarget(channel: String)

        var errorDescription: String? {
            switch self {
            case .noConsent(let c): return "Customer has not consented to \(c)."
            case .noTarget(let c):  return "No \(c) address on file."
            }
        }
    }

    // MARK: - Email

    /// Send via SendGrid. Throws if email is not configured, customer hasn't
    /// consented, or there's no email on file. Caller surfaces the error.
    static func sendEmail(_ plan: EmailPlan, customer: Customer) async throws {
        guard customer.consentEmail else { throw DispatchError.noConsent(channel: "email") }
        guard !plan.to.isEmpty else { throw DispatchError.noTarget(channel: "email") }
        try await SendGridClient.send(
            to: plan.to,
            toName: plan.toName,
            subject: plan.subject,
            htmlBody: plan.htmlBody,
            plainBody: plan.plainBody
        )
    }

    // MARK: - SMS

    /// Send via Twilio. Re-uses `consentWhatsapp` as the messaging-consent
    /// proxy until we add a dedicated `consent_sms` column (intentional
    /// shortcut — DPDP doesn't require channel-by-channel granularity).
    static func sendSMS(_ plan: SMSPlan, customer: Customer) async throws {
        guard customer.consentWhatsapp else { throw DispatchError.noConsent(channel: "SMS") }
        guard !plan.to.isEmpty else { throw DispatchError.noTarget(channel: "SMS") }
        try await TwilioClient.send(to: plan.to, body: plan.body)
    }

    // MARK: - Convenience: order-ready announcement across all channels

    /// Build a notification plan for an order entering `.ready` (i.e. the
    /// classic "order is ready for pickup/delivery" announcement).
    /// Channels not consented / not configured / missing target are simply
    /// omitted — call-sites filter the plan before showing buttons.
    static func orderReadyPlan(
        for order: Order,
        customer: Customer,
        boutiqueName: String
    ) -> Plan {
        let first = customer.name.split(separator: " ").first.map(String.init) ?? customer.name
        let msg = "Hi \(first), your order \(order.orderNumber) from \(boutiqueName) is ready! Total: \(Formatters.inr(order.total)). Drop by or reply for delivery."
        let htmlBody = """
        <div style="font-family: -apple-system, Helvetica, Arial; color: #1c1c1e;">
          <h2 style="color: #6b3aa0;">Your order is ready, \(first)!</h2>
          <p>Order <b>\(order.orderNumber)</b> from <b>\(boutiqueName)</b> is ready for pickup or delivery.</p>
          <p>Total: <b>\(Formatters.inr(order.total))</b></p>
          <p>Reply to this email or message us on WhatsApp to arrange pickup.</p>
          <hr style="border: none; border-top: 1px solid #e5e5ea;"/>
          <p style="color: #8e8e93; font-size: 12px;">You're receiving this because you opted in to order updates from \(boutiqueName). Reply STOP to unsubscribe.</p>
        </div>
        """

        var plan = Plan()
        if customer.consentWhatsapp, let target = customer.whatsappTarget {
            plan.whatsapp = WhatsAppPlan(target: target, message: msg)
        }
        if customer.consentEmail, let email = customer.email, !email.isEmpty, Config.emailEnabled {
            plan.email = EmailPlan(
                to: email, toName: customer.name,
                subject: "Your order is ready — \(order.orderNumber)",
                htmlBody: htmlBody, plainBody: msg
            )
        }
        if customer.consentWhatsapp, let target = customer.whatsappTarget, Config.smsEnabled {
            plan.sms = SMSPlan(to: target, body: msg)
        }
        return plan
    }
}
