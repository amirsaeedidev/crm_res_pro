-- Cover inventory-side foreign keys surfaced by the Supabase performance advisor.
begin;
create index if not exists inventory_alert_settings_updated_by_idx
  on public.inventory_alert_settings(updated_by) where updated_by is not null;
create index if not exists inventory_import_batches_created_by_idx
  on public.inventory_import_batches(created_by) where created_by is not null;
create index if not exists inventory_purchases_created_by_idx
  on public.inventory_purchases(created_by) where created_by is not null;
create index if not exists inventory_stock_count_items_material_idx
  on public.inventory_stock_count_items(material_id);
create index if not exists inventory_stock_counts_created_by_idx
  on public.inventory_stock_counts(created_by) where created_by is not null;
create index if not exists inventory_suppliers_created_by_idx
  on public.inventory_suppliers(created_by) where created_by is not null;
commit;
