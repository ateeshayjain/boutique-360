-- 0027 — separate WhatsApp number from contact phone.
--
-- Until now the WA number was implicitly `customers.phone` gated by
-- `consent_whatsapp`. Real boutiques routinely have a landline/billing
-- phone different from the family WA number — and invoices need the
-- billing phone, not the WA one. Separating them now (nullable, defaults
-- to phone at read time in the app) costs nothing and unblocks the
-- notifications work.
--
-- We do NOT enforce E.164 here — the app validates loosely (Indian
-- 10-digit + optional +91) so the column accepts whatever the user typed.
alter table public.customers
  add column if not exists whatsapp_phone text;

comment on column public.customers.whatsapp_phone is
  'Customer WhatsApp number. When null, the app falls back to customers.phone for WA send.';
