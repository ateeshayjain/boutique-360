-- Plan 1, Task 1.18 — dev seed
insert into public.boutiques (id, name, slug, gstin, brand_color_hex)
values ('00000000-0000-0000-0000-000000000001', 'Aditi Designer Studio', 'aditi-designer-studio', '07AAAAA0000A1Z5', '#7C2D3C')
on conflict (id) do nothing;

insert into public.loyalty_tiers (boutique_id, name, min_lifetime_value, min_orders, points_multiplier, perks_json, color_hex, sort_order) values
('00000000-0000-0000-0000-000000000001', 'Silver',   0,      0,  1.0, '{"free_shipping": false, "birthday_voucher_amount": 0}'::jsonb,    '#C0C0C0', 1),
('00000000-0000-0000-0000-000000000001', 'Gold',     50000,  3,  1.5, '{"free_shipping": true,  "birthday_voucher_amount": 500}'::jsonb,  '#D4AF37', 2),
('00000000-0000-0000-0000-000000000001', 'Platinum', 200000, 10, 2.0, '{"free_shipping": true,  "birthday_voucher_amount": 2000, "early_access": true, "priority_support": true}'::jsonb, '#E5E4E2', 3)
on conflict do nothing;
