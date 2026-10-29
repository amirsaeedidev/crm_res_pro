-- Previous purchase rows have no reliable original unit price after historical cost allocation.
-- Keep unknown historical invoice prices NULL; newly recorded purchases store the exact invoice unit price.
update public.inventory_purchase_items
set entered_unit_cost = null
where created_at < timestamptz '2026-10-29 11:22:10+00'
  and entered_unit_cost is not null;
