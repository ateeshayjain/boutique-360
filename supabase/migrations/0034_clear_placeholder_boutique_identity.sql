-- 0034 — clear the placeholder tax identity seeded by 0023.
--
-- '07AAAAA0000A1Z5' fails the GSTIN mod-36 checksum (its check character
-- should be '4'), so it was never a real registration — but the app treats a
-- non-empty GSTIN as "invoicing enabled" and had been printing it on GST
-- invoices, which are statutory documents.
--
-- Nulling it makes the app's own rule do the right thing: no GSTIN, no
-- invoicing, plus a one-time prompt (GSTINPromptCard) to add the real one.
-- Paired with the checksum added to GSTINValidator on 2026-08-01, which stops
-- a value of this shape being entered again.
--
-- The WHERE clauses match only the known placeholders, so a real value entered
-- by the owner in the meantime is never touched.
--
-- `place_of_supply = 'Delhi'` is deliberately left alone: a state name is a
-- correctable business fact, not a fabricated identifier, and it is inert
-- while invoicing is disabled.

update public.boutiques
   set gstin = null
 where gstin in ('07AAAAA0000A1Z5', '07AAACA0000A1Z5');

update public.boutiques
   set address = null
 where address = 'Shop 12, Lajpat Nagar, New Delhi 110024';
