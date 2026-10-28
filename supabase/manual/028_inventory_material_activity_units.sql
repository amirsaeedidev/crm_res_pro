-- Material activity report and safe metric-unit conversion for supplier purchases.
begin;

alter table public.inventory_purchase_items
  add column if not exists entered_quantity numeric(14,3),
  add column if not exists entered_unit text,
  add column if not exists conversion_factor numeric(14,6) not null default 1;

create or replace function public.get_inventory_material_activity_report(
 p_start_date timestamptz,
 p_end_date timestamptz
) returns json
language plpgsql security invoker set search_path = '' as $$
declare v_rows json;
begin
 if not (select public.is_admin()) then raise exception 'Administrator access required' using errcode='42501'; end if;
 if p_start_date is null or p_end_date is null or p_end_date < p_start_date then raise exception 'Invalid report date range' using errcode='22023'; end if;
 select coalesce(json_agg(json_build_object(
   'material_id',m.id,'material_name',m.name,'stock_unit',m.unit,
   'current_stock',m.quantity_on_hand,'unit_cost',m.unit_cost,
   'current_stock_value',round(m.quantity_on_hand*m.unit_cost,2),
   'purchased_quantity',coalesce(p.purchased_quantity,0),
   'purchase_cost',coalesce(p.purchase_cost,0),
   'consumed_quantity',coalesce(t.consumed_quantity,0),
   'consumption_cost',coalesce(t.consumption_cost,0),
   'waste_quantity',coalesce(t.waste_quantity,0),
   'waste_cost',coalesce(t.waste_cost,0),
   'return_quantity',coalesce(t.return_quantity,0),
   'return_cost',coalesce(t.return_cost,0)
 ) order by m.name),'[]'::json)
 into v_rows
 from public.inventory_materials m
 left join lateral (
   select sum(i.quantity) purchased_quantity, sum(i.line_total) purchase_cost
   from public.inventory_purchase_items i join public.inventory_purchases h on h.id=i.purchase_id
   where i.material_id=m.id and h.status='received'
     and h.purchase_date >= p_start_date::date and h.purchase_date <= p_end_date::date
 ) p on true
 left join lateral (
   select
    coalesce(sum(case when x.transaction_type='order_usage' then abs(x.quantity_delta) else 0 end),0) consumed_quantity,
    coalesce(sum(case when x.transaction_type='order_usage' then abs(x.total_cost) else 0 end),0) consumption_cost,
    coalesce(sum(case when x.transaction_type='waste' then abs(x.quantity_delta) else 0 end),0) waste_quantity,
    coalesce(sum(case when x.transaction_type='waste' then abs(x.total_cost) else 0 end),0) waste_cost,
    coalesce(sum(case when x.transaction_type='return' then abs(x.quantity_delta) else 0 end),0) return_quantity,
    coalesce(sum(case when x.transaction_type='return' then abs(x.total_cost) else 0 end),0) return_cost
   from public.inventory_transactions x
   where x.material_id=m.id and x.created_at >= p_start_date and x.created_at <= p_end_date
 ) t on true
 where m.is_active=true;
 return json_build_object('id','inventory_material_activity','type','inventory_material_activity',
   'summary',json_build_object('material_count',json_array_length(v_rows)),
   'chart_data',v_rows,'start_date',p_start_date,'end_date',p_end_date,'created_at',now());
end; $$;
revoke all on function public.get_inventory_material_activity_report(timestamptz,timestamptz) from public,anon;
grant execute on function public.get_inventory_material_activity_report(timestamptz,timestamptz) to authenticated;

-- Extend the purchase RPC: entered quantities are converted to the material's stock unit.
create or replace function public.admin_record_inventory_purchase(
 p_supplier_id uuid, p_invoice_number text, p_purchase_date date, p_items jsonb,
 p_discount_amount numeric default 0, p_shipping_amount numeric default 0,
 p_paid_amount numeric default 0, p_notes text default ''
) returns uuid language plpgsql security invoker set search_path = '' as $$
declare
 v_purchase_id uuid; v_item jsonb; v_material_id uuid; v_quantity numeric;
 v_entered_qty numeric; v_entered_cost numeric; v_unit_cost numeric;
 v_entered_unit text; v_stock_unit text; v_entered_factor numeric; v_stock_factor numeric;
 v_ratio numeric; v_subtotal numeric := 0; v_total numeric;
 v_discount numeric := coalesce(p_discount_amount,0); v_shipping numeric := coalesce(p_shipping_amount,0);
 v_paid numeric := coalesce(p_paid_amount,0); v_reason text;
begin
 if not (select public.is_admin()) then raise exception 'Administrator access required' using errcode='42501'; end if;
 if p_supplier_id is null or not exists(select 1 from public.inventory_suppliers where id=p_supplier_id and is_active) then raise exception 'Supplier is missing or inactive' using errcode='22023'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'At least one purchase item is required' using errcode='22023'; end if;
 if v_discount<0 or v_shipping<0 or v_paid<0 then raise exception 'Purchase amounts cannot be negative' using errcode='22023'; end if;
 for v_item in select value from jsonb_array_elements(p_items) loop
   v_material_id := (v_item->>'material_id')::uuid;
   v_entered_qty := (v_item->>'quantity')::numeric;
   v_entered_cost := (v_item->>'unit_cost')::numeric;
   v_entered_unit := coalesce(v_item->>'purchase_unit','');
   select unit into v_stock_unit from public.inventory_materials where id=v_material_id and is_active=true;
   if not found then raise exception 'Unknown or inactive inventory material' using errcode='22023'; end if;
   v_entered_factor := case v_entered_unit when 'g' then 1 when 'kg' then 1000 when 'ml' then 1 when 'l' then 1000 when 'unit' then 1 else null end;
   v_stock_factor := case v_stock_unit when 'g' then 1 when 'kg' then 1000 when 'ml' then 1 when 'l' then 1000 when 'unit' then 1 else null end;
   if v_entered_factor is null or v_stock_factor is null then
     if v_entered_unit <> v_stock_unit then raise exception 'Unit conversion is only supported for g/kg, ml/l and identical units; pack/box need a defined conversion.' using errcode='22023'; end if;
     v_entered_factor:=1; v_stock_factor:=1;
   end if;
   if (v_entered_unit in ('g','kg') and v_stock_unit not in ('g','kg')) or
      (v_entered_unit in ('ml','l') and v_stock_unit not in ('ml','l')) or
      (v_entered_unit='unit' and v_stock_unit<>'unit') or
      (v_entered_unit not in ('g','kg','ml','l','unit') and v_entered_unit<>v_stock_unit) then
     raise exception 'Incompatible purchase unit % for stock unit %',v_entered_unit,v_stock_unit using errcode='22023';
   end if;
   if v_entered_qty<=0 or v_entered_cost<0 then raise exception 'Invalid quantity or unit cost' using errcode='22023'; end if;
   v_ratio:=v_entered_factor/v_stock_factor;
   v_subtotal:=v_subtotal+round(v_entered_qty*v_entered_cost,2);
 end loop;
 v_total:=greatest(0,v_subtotal-v_discount+v_shipping);
 if v_paid>v_total then raise exception 'Paid amount cannot exceed purchase total' using errcode='22023'; end if;
 insert into public.inventory_purchases(supplier_id,invoice_number,purchase_date,subtotal,discount_amount,shipping_amount,total_amount,paid_amount,payment_status,notes,created_by)
 values(p_supplier_id,coalesce(trim(p_invoice_number),''),coalesce(p_purchase_date,current_date),v_subtotal,v_discount,v_shipping,v_total,v_paid,
 case when v_paid=0 then 'unpaid' when v_paid>=v_total then 'paid' else 'partial' end,coalesce(p_notes,''),auth.uid()) returning id into v_purchase_id;
 for v_item in select value from jsonb_array_elements(p_items) loop
   v_material_id := (v_item->>'material_id')::uuid;
   v_entered_qty := (v_item->>'quantity')::numeric;
   v_entered_cost := (v_item->>'unit_cost')::numeric;
   v_entered_unit := coalesce(v_item->>'purchase_unit','');
   select unit into v_stock_unit from public.inventory_materials where id=v_material_id and is_active=true;
   v_entered_factor:=case v_entered_unit when 'g' then 1 when 'kg' then 1000 when 'ml' then 1 when 'l' then 1000 when 'unit' then 1 else 1 end;
   v_stock_factor:=case v_stock_unit when 'g' then 1 when 'kg' then 1000 when 'ml' then 1 when 'l' then 1000 when 'unit' then 1 else 1 end;
   v_ratio:=v_entered_factor/v_stock_factor;
   v_quantity:=round(v_entered_qty*v_ratio,3);
   v_unit_cost:=case when v_ratio>0 then round(v_entered_cost/v_ratio,2) else v_entered_cost end;
   insert into public.inventory_purchase_items(purchase_id,material_id,quantity,unit_cost,entered_quantity,entered_unit,conversion_factor)
   values(v_purchase_id,v_material_id,v_quantity,v_unit_cost,v_entered_qty,v_entered_unit,v_ratio);
   v_reason:='خرید تامین‌کننده؛ سند '||coalesce(nullif(trim(p_invoice_number),''),v_purchase_id::text);
   perform public.admin_receive_inventory(v_material_id,v_quantity,v_unit_cost,v_reason);
 end loop;
 return v_purchase_id;
end; $$;
revoke all on function public.admin_record_inventory_purchase(uuid,text,date,jsonb,numeric,numeric,numeric,text) from public,anon;
grant execute on function public.admin_record_inventory_purchase(uuid,text,date,jsonb,numeric,numeric,numeric,text) to authenticated;
commit;
