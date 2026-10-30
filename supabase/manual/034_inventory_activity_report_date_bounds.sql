-- Use an exclusive upper bound for inventory activity reports to avoid
-- counting the first instant of the following day twice.
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
  if p_start_date is null or p_end_date is null or p_end_date <= p_start_date then
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
      and x.created_at < p_end_date
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
      and x.created_at < p_end_date
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
