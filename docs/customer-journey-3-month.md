# Customer Journey — 3 Months, 4 Orders ("Priya")

A composite-but-realistic journey used to reason about product coverage:
one customer, a daughter's wedding driving multiple orders, each order with
a different lifecycle (smooth / early / late / repeat). Referenced when
prioritising back-of-house features (buffer planning, alterations, delivery
modes).

## Timeline overview (13 weeks)

```
Week:        1    2    3    4    5    6    7    8    9   10   11   12   13
             |-- July ----------|-- August ---------|-- September --------|

Relationship 👤IG                📞check-in                    🎉wedding 💬thanks
Lehenga      [design·VTO][——— production 6 wk ———————][fit×2][pickup]
Haldi set                   [dsn][ prod 2wk ][ship→]
Reception                             [dsn][— prod 3wk —][alt×2][LATE 3d][hand-dlv]
Anniversary                                                        [dsn][1wk→]
```

## Order 1 — Sangeet lehenga · ₹1,45,000 · heavy zardozi

| Week | Activity | App surface |
|---|---|---|
| 1 | Instagram DM → inquiry logged (source: instagram), consent + WA # captured | Inquiries, CustomerFormView |
| 1 | Sketch over kurta template + emerald silk fabric overlay → AI render → **virtual try-on closes the sale** | SketchCanvasView, GarmentTemplate, RenderView, VirtualTryOnView |
| 1 | 50% advance recorded, order created, Hinglish job card to karigar | PaymentsSectionView, OrdersService (atomic RPC), JobCardPDFGenerator |
| 4–9 | 6 weeks zardozi production; 2 WIP checks at workshop | Order status transitions |
| 10 | Fitting ×2 — blouse taken in once | AlterationsService |
| 11 | Boutique pickup: final try-on, balance via payment link, GST invoice | RazorpayClient, InvoicePDFGenerator |

**Outcome: on time.** Buffer week between fitting and the event absorbed the alteration.

## Order 2 — Haldi kurta set · ₹28,000 · light chikankari

| Week | Activity | App surface |
|---|---|---|
| 5 | Added during a fitting visit. Measurements already on file → 20-minute sale, not 2 hours | Measurements history |
| 6–7 | 2-week production, finishes 4 days **early** | — |
| 8 | Customer is in Pune → **courier ship**, tracking URL on WhatsApp, balance via Razorpay link | fulfillmentMethod=ship, trackingUrl, WhatsAppShareHelper |

**Outcome: early.** The compounding CRM effect: order #2's acquisition cost is one conversation.

## Order 3 — Reception blouse + drape · ₹52,000 · kanjivaram

| Week | Activity | App surface |
|---|---|---|
| 7 | Pinterest screenshot re-rendered in her own silk | ReferenceStudioView |
| 8–10 | 3-week production — **no buffer before the reception date** | — |
| 11 | Fitting fails: sleeve cut wrong → 2 alteration rounds back-to-back | AlterationsService |
| 12 | Runs **3 days late** against a hard event date. Owner calls twice, reorders karigar queue | Status board surfaces the slip |
| 12 | **Hand-delivered** by the boutique 2 days before the reception | — |

**Outcome: late but saved.** Root cause: no buffer week between planned
completion and the event. See "Lessons" below.

## Order 4 — Anniversary blouse · ₹9,500 · repeat

| Week | Activity | App surface |
|---|---|---|
| 12 | Wedding happens. Congratulations + lookbook photos sent | ImportantDates, lookbook |
| 13 | "Suggest a look" surfaces the upcoming anniversary → one templated WhatsApp → yes | StyleSuggestionsSheet (Wave 6), important dates |
| 13→ | 1-week turnaround, measurements on file, **no fitting needed** | — |

**Outcome: zero-acquisition-cost repeat.** Month 3's order took one message.

## Totals

- 4 orders · **₹2,34,500** revenue · ~14 owner-customer touchpoints
- 3 delivery modes: boutique pickup, courier, hand-delivery
- 3 alteration rounds across 2 garments (normal for custom work)
- 1 late delivery — caught on the board, managed, not discovered at pickup

## Lessons → product backlog

1. **Event-date back-planning (the week-11 failure).** Orders tied to a hard
   event date should plan backwards: event − delivery buffer − alteration
   buffer − production = latest safe start. The app has due dates on job
   cards but no event anchor. *Candidate feature: `event_date` on Order +
   computed "latest safe start" warning at order creation.*
2. **Buffer rule of thumb:** heavy garments got a buffer week and survived
   their alteration; the reception blouse had none and slipped. Suggest
   1 buffer week per fitting expected.
3. **Repeat velocity:** orders 2 and 4 were fast *because* measurements and
   style history were on file. Everything that shortens the second sale
   (measurement history, timeline, AI suggestions) compounds.
4. **Delivery mode varies per order, not per customer.** Same customer used
   all three modes in one season — pickup/ship/hand-deliver must stay
   order-level (it is: `fulfillment_method`).
