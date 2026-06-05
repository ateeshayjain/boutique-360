# User Journeys — Boutique 360

**Single user persona**: the boutique owner. They are simultaneously the designer, the salesperson, the accountant, and the relationship manager. They run a 1-2 person operation in a Tier-1/Tier-2 Indian city. Customers never touch the iPad — they interact via WhatsApp, in-person visits, or (future) the public website.

This document describes the **actual daily reality** of the owner, not idealized flows. Every feature in the app should serve one of these journeys; features that don't are bloat.

---

## Persona snapshot

| Trait | Value |
|---|---|
| Role | Owner + designer + salesperson + occasional tailor |
| Device | iPad (10th gen or M-series), Apple Pencil, occasionally Mac for invoicing |
| Hours | 11am–9pm, 6 days/week, peak 6–9pm |
| Customers per week | 30–60 (Tier-1), 15–25 (Tier-2) |
| Active orders at any time | 20–80 |
| Comfort with apps | Used to WhatsApp Business, Tally, Zoho Books. Wary of complexity. |
| Connectivity | Wi-Fi at the boutique, mobile data on the iPad as backup. Sometimes flaky. |
| Languages | Hindi + English mixed; designs are described in Hinglish |

---

## Journey 1 — The morning briefing (8:30am, before opening)

**Context:** Owner is having chai at home. Wants to know "what does today look like?"

| Step | Action | App surface | Friction → fix |
|------|--------|-------------|-----------------|
| 1 | Opens app | Dashboard | If app comes back from background and dashboard is stale → H4 scenePhase observer triggers refresh |
| 2 | Reads "Good morning Saturday 26 Jan" greeting + boutique name | DashboardView header | — |
| 3 | Sees Today's revenue card (₹0 — it's early), today's appointments, overdue payments | DashboardView | If Supabase unreachable → H1 stale-data banner instead of misleading ₹0 |
| 4 | Sees "3 fittings today" → mentally allocates afternoon | Dashboard quick stats | — |
| 5 | Sees "2 payments overdue" → texts those customers from WhatsApp before opening shop | Dashboard overdue list + WhatsAppShareHelper from CustomerDetailView | — |
| 6 | Sees birthday today: "Priya Mehta — Anniversary" → uses WhatsApp button | Important Dates list | A5 fix from Batch A |

**Trust requirement:** Numbers shown must be authoritative. If the load failed, the banner must say so — owner cannot waste the chai hour on wrong data.

---

## Journey 2 — A new customer walks in (afternoon, ~3pm)

**Context:** Customer enters with cousin's wedding 2 months out, wants a lehenga. Owner is at the iPad on a stool, customer sits across.

| Step | Action | App surface | Pre-fix risk |
|------|--------|-------------|--------------|
| 1 | Taps "+ New customer" | CustomersListView toolbar | — |
| 2 | Enters name, phone, WhatsApp consent toggle (DPDP explicit consent) | CustomerFormView | — |
| 3 | Taps "+ New inquiry" from the just-created profile | CustomerDetailView quick actions | L6: inquiry numbers were random — collision risk fixed |
| 4 | Picks occasion = "Cousin's wedding", event date, budget = ₹40k–60k | InquiryFormView | M7: date format used POSIX-locked formatter now |
| 5 | Customer scrolls Pinterest on her phone, owner sketches with Pencil on Boutique 360 | SketchCanvasView | PKToolPicker deprecation fixed |
| 6 | Saves sketch → "AI render" button | DesignDetailView | — |
| 7 | Gemini renders the lehenga (≈30s spinner) | RenderView | — |
| 8 | Owner taps Share → WhatsApps the AI preview to customer | RenderView ShareLink | A1 fix — native ShareLink |
| 9 | Customer wants to see herself in it → owner asks consent verbally → toggles DPDP consent | VirtualTryOnView | B4: consent timestamp captured at toggle moment, not after upload |
| 10 | Picks customer photo from camera roll, generates VTO | VTO flow | B2: customer photo persisted via (bucket, path), not signed URL |
| 11 | Owner shares VTO result to customer's WhatsApp | VTO ShareLink | A2 fix |
| 12 | Customer says "yes, take measurements" → Measurements button | CustomerDetailView | — |
| 13 | Owner enters bust/waist/hip in inches | MeasurementFormView | — |
| 14 | Inquiry moves to "Measurements" column in Kanban | InquiriesListView Kanban | H8: only allowed transitions appear in menu |

**Outcome:** Inquiry created, design sketched + rendered + virtually tried on, measurements captured. Owner converts to order when customer confirms (often next day after consulting husband).

---

## Journey 3 — Converting inquiry → order + advance payment (next day)

**Context:** Customer texts "Haan kar do, advance kitna chahiye?" Owner is mid-stitching another lehenga and quickly switches to iPad.

| Step | Action | App surface | Pre-fix risk |
|------|--------|-------------|--------------|
| 1 | Inquiries Kanban → finds the lehenga inquiry → menu → "Move to Quoted" | InquiriesListView | H8 enforcement |
| 2 | Customer detail → "+ Create order from inquiry" | (planned next pass) | — |
| 3 | OrderCreate sheet — auto-fills customer, qty 1, ₹45,000 + 5% GST (loaded from boutique default) | OrderCreateView | L2: GST rate now from `boutique.defaultGstRate` not hardcoded 5% |
| 4 | Picks Pickup (default) vs Ship | OrderCreateView Picker | H9: typed `FulfillmentMethod` enum |
| 5 | Hits Create → Postgres RPC atomically inserts order + line item + links inquiry | OrdersService.create → `create_order_with_items` RPC | B6: was 3 separate inserts; partial failure = orphan rows |
| 6 | Order detail → Payments section → "Record payment" → ₹20,000 advance, UPI method | PaymentsSectionView → RecordPaymentView | B1: if load fails, button blocked + banner shown |
| 7 | Receipt of ₹20,000 visible. Balance ₹27,250 shown | PaymentsSectionView | L7: balance rounded to paise — no sub-cent drift |
| 8 | Owner taps "Send WhatsApp confirmation" → templated Hinglish message | OrderDetailView WhatsApp button | A3 + H2: error surfaced on failure, retry possible |

**Trust requirement:** Money flows must never silently fail. Either the payment is recorded or the owner is loudly told it isn't.

---

## Journey 4 — Sending to workshop (job card)

**Context:** Order confirmed, advance taken. Owner now needs to brief the karigar (master tailor) without going to the workshop.

| Step | Action | App surface | Pre-fix risk |
|------|--------|-------------|--------------|
| 1 | DesignDetailView → "Send to workshop (Job Card)" | DesignDetailView | — |
| 2 | JobCardComposer opens, auto-pulls measurements matching garment type | JobCardComposerView.load() | M2: if load fails, "Create & open PDF" blocked + error surfaced. Karigar won't get a blank-measurements job card. |
| 3 | Owner adds fabrics: 6m Banarasi silk (main, ivory) + 2m organza (lining) | JobCardComposer | — |
| 4 | Adds embellishments note: "Heavy zari on yoke + border. Sequin work on dupatta." | JobCardComposer | — |
| 5 | Sets due date 14 days out | DatePicker | M7: date stored via Formatters.postgresDate |
| 6 | Taps "Generate Hinglish brief" → Gemini composes karigar-language summary | GeminiService.generateTailorBrief | L3: URL construction guarded, won't crash on missing key |
| 7 | Edits the AI brief (adds "Salma extra deni hai, customer ka allergy hai polyester se") | TextEditor | — |
| 8 | Save → PDF preview opens with structured visual top + Hinglish brief bottom | JobCardPDFGenerator + JobCardPreviewView | — |
| 9 | ShareLink → WhatsApp to karigar | JobCardPreviewView toolbar | — |

**Trust requirement:** The karigar gets a complete brief or none — never a job card with missing sketches or empty measurements (would mean wrong garment).

---

## Journey 5 — Customer asks "is my lehenga ready?" (WhatsApp, anytime)

**Context:** Customer messages 4 days before her event. Owner is at home; opens iPad.

| Step | Action | App surface |
|------|--------|-------------|
| 1 | Customers list → searches "Priya" | CustomersListView (server-side debounced search) |
| 2 | Customer detail → Journey section shows: inquiry → quoted → confirmed → order placed → payment received → job card issued (5 days ago) | CustomerDetailView Journey | One glance answers "where is this order?" — B48 timeline replaces 3-status-field fragmentation |
| 3 | Owner taps the WhatsApp button: "Hi Priya, your lehenga is in finishing stage, will be ready by Friday." | CustomerDetailView quick actions |
| 4 | Or: opens the Order detail → status → Mark Ready → templated "ready for pickup" message | OrderDetailView WhatsApp section | A3: occasion-aware Hinglish |

**Trust requirement:** The Journey feed must be accurate. If timeline aggregation partially failed, user must know (currently best-effort — improvement opportunity).

---

## Journey 6 — End-of-day reconciliation (9pm closing)

**Context:** Closing time. Cash drawer has notes; UPI app shows captures. Owner wants to know "what happened today?"

| Step | Action | App surface |
|------|--------|-------------|
| 1 | Dashboard → Today's revenue card | DashboardView |
| 2 | Sees ₹47,500 total · Cash ₹12,000 · UPI ₹35,500 · 2 new orders · 1 new customer | Today card | Matches cash drawer count |
| 3 | Sees today's appointments — taps "Done" on each completed | CalendarView swipe action | H2: error surfaced on failure |
| 4 | Sees payments overdue list — texts 1 customer reminder via WhatsApp | Dashboard | A4 fix: balance reminder in PaymentsSectionView |

---

## Journey 7 — Proactive outreach (Friday afternoon, slow hour)

**Context:** Owner has 30 min between fittings. Wants to be productive.

| Step | Action | App surface |
|------|--------|-------------|
| 1 | Important Dates list → sees 4 birthdays + 2 anniversaries this month | ImportantDatesListView |
| 2 | Per row, taps the green message icon → occasion-aware Hinglish greeting opens in WhatsApp | A5 fix |
| 3 | Personalizes the message (adds personal note) → sends | WhatsApp |
| 4 | Returns to app → next birthday | — |

**Outcome:** Free 30 min becomes 6 personal nudges → typically 1-2 customers visit within a week.

---

## Journey 8 — End-of-month GST filing (1st of next month, CA emails)

**Context:** CA wants January data by 5 Feb. Owner opens app, generates report.

| Step | Action | App surface | Pre-fix risk |
|------|--------|-------------|--------------|
| 1 | Settings → GST report → picks January 2026 | SettingsView GST section | — |
| 2 | Taps "Export GST CSV for filing" | SettingsView | — |
| 3 | If Supabase unreachable, gets error banner; doesn't get an empty CSV | SettingsView | H11: function throws; previous behavior was silent ₹0 turnover CSV |
| 4 | If 3 shipped orders are flagged → "spot-check inter-state IGST" warning shown | SettingsView | H10: surfaces inter-state risk |
| 5 | Shares CSV via WhatsApp / email to CA | ShareLink | — |
| 6 | CA pastes into GSTR-1 portal | (outside app) |

**Trust requirement:** Wrong CSV → wrong filing → ₹10k+ penalty. The empty-CSV-on-failure was a real liability; now refuses to generate on failure.

---

## Anti-journeys (what we deliberately don't do)

| Anti-pattern | Why excluded |
|---|---|
| Customer-facing iPad — let customer browse catalog | Customers don't want to touch a designer's iPad. WhatsApp + future public web does this. |
| Multi-user role separation | This boutique has 1 owner + 0–1 helper. Role complexity adds confusion. |
| Generic e-commerce features (wishlist, ratings) | Bridal/couture is bespoke. Inventory is fabric, not SKUs. |
| Push notifications to customers | Owner sends WhatsApp manually — keeps tone personal. Automated pings feel like spam. |
| In-app analytics dashboards beyond "today's revenue" | Owner doesn't want a Mixpanel-style UI. CA does the monthly tally. |
