-- Inventory integrity and material activity report fixes.
begin;

-- A supplier invoice must not be posted twice for the same supplier.
create unique index if not exists inventory_purchases_supplier_invoice_uq
  on public.inventory_purchases (supplier_id, lower(trim(invoice_number)))
  where status = 'received' and trim(invoice_number) <> '';

-- Once movements, recipes or purchase history exist, the stock unit is immutable.
-- Changing kg to g without converting historical quantities would corrupt stock and costing.
create or replace function public.prevent_inventory_material_unit_change()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.unit is distinct from old.unit
     and (
       old.quantity_on_hand <> 0
       or old.reorder_level <> 0
       or exists (select 1 from public.inventory_transactions t where t.material_id = old.id)
       or exists (select 1 from public.product_recipes r where r.material_id = old.id)
       or exists (select 1 from public.inventory_purchase_items i where i.material_id = old.id)
     ) then
    raise exception 'واحد پایه ماده اولیه پس از ثبت موجودی، خرید یا دستور مصرف قابل تغییر نیست؛ ماده جدید با واحد صحیح ایجاد کنید.'
      using errcode = '22023';
  end if;
  return new;
end;
$$;

drop trigger if exists inventory_material_unit_immutable on public.inventory_materials;
create trigger inventory_material_unit_immutable
before update of unit on public.inventory_materials
for each row execute function public.prevent_inventory_material_unit_change();

-- Purchase metrics are read from the inventory ledger so manual stock receipts
-- and supplier invoices are counted once, using real timestamp boundaries.
create or replace function public.get_inventory_material_activity_report(
  p_start_date timestamptz,
  p_end_date timestamptz
)
returns json
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_rows json;
begin
  if not (select public.is_admin()) then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'Invalid report date range' using errcode = '22023';
  end if;

  select coalesce(
    json_agg(
      json_build_object(
        'material_id', m.id,
        'material_name', m.name,
        'stock_unit', m.unit,
        'current_stock', m.quantity_on_hand,
        'unit_cost', m.unit_cost,
        'current_stock_value', round(m.quantity_on_hand * m.unit_cost, 2),
        'purchased_quantity', coalesce(p.purchased_quantity, 0),
        'purchase_cost', coalesce(p.purchase_cost, 0),
        'consumed_quantity', coalesce(t.consumed_quantity, 0),
        'consumption_cost', coalesce(t.consumption_cost, 0),
        'waste_quantity', coalesce(t.waste_quantity, 0),
        'waste_cost', coalesce(t.waste_cost, 0),
        'return_quantity', coalesce(t.return_quantity, 0),
        'return_cost', coalesce(t.return_cost, 0)
      )
      order by m.name
    ),
    '[]'::json
  )
  into v_rows
  from public.inventory_materials m
  left join lateral (
    select
      coalesce(sum(abs(x.quantity_delta)), 0) as purchased_quantity,
      coalesce(sum(abs(x.total_cost)), 0) as purchase_cost
    from public.inventory_transactions x
    where x.material_id = m.id
      and x.transaction_type = 'purchase'
      and x.created_at >= p_start_date
      and x.created_at <= p_end_date
  ) p on true
  left join lateral (
    select
      coalesce(sum(case when x.transaction_type = 'order_usage' then abs(x.quantity_delta) else 0 end), 0) as consumed_quantity,
      coalesce(sum(case when x.transaction_type = 'order_usage' then abs(x.total_cost) else 0 end), 0) as consumption_cost,
      coalesce(sum(case when x.transaction_type = 'waste' then abs(x.quantity_delta) else 0 end), 0) as waste_quantity,
      coalesce(sum(case when x.transaction_type = 'waste' then abs(x.total_cost) else 0 end), 0) as waste_cost,
      coalesce(sum(case when x.transaction_type = 'return' then abs(x.quantity_delta) else 0 end), 0) as return_quantity,
      coalesce(sum(case when x.transaction_type = 'return' then abs(x.total_cost) else 0 end), 0) as return_cost
    from public.inventory_transactions x
    where x.material_id = m.id
      and x.created_at >= p_start_date
      and x.created_at <= p_end_date
  ) t on true
  where m.is_active = true;

  return json_build_object(
    'id', 'inventory_material_activity',
    'type', 'inventory_material_activity',
    'summary', json_build_object('material_count', json_array_length(v_rows)),
    'chart_data', v_rows,
    'start_date', p_start_date,
    'end_date', p_end_date,
    'created_at', now()
  );
end;
$$;

revoke all on function public.get_inventory_material_activity_report(timestamptz, timestamptz) from public, anon;
grant execute on function public.get_inventory_material_activity_report(timestamptz, timestamptz) to authenticated;


-- Keep the CRM's global-alert preferences synchronized while the inventory tab is open.
do $
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'inventory_alert_settings'
     ) then
    execute 'alter publication supabase_realtime add table public.inventory_alert_settings';
  end if;
end;
$;

commit;
