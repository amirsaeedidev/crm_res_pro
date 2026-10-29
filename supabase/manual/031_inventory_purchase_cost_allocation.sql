-- Preserve supplier invoice unit prices while allocating invoice discounts/shipping to stock valuation.
begin;

alter table public.inventory_purchase_items
  add column if not exists entered_unit_cost numeric(14,2);

create or replace function public.admin_record_inventory_purchase(
  p_supplier_id uuid,
  p_invoice_number text,
  p_purchase_date date,
  p_items jsonb,
  p_discount_amount numeric default 0,
  p_shipping_amount numeric default 0,
  p_paid_amount numeric default 0,
  p_notes text default ''
) returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_purchase_id uuid;
  v_item jsonb;
  v_material_id uuid;
  v_quantity numeric(14,3);
  v_entered_qty numeric(14,3);
  v_entered_cost numeric(14,2);
  v_unit_cost numeric(14,2);
  v_entered_unit text;
  v_stock_unit text;
  v_entered_factor numeric;
  v_stock_factor numeric;
  v_ratio numeric;
  v_subtotal numeric := 0;
  v_total numeric;
  v_cost_factor numeric := 1;
  v_discount numeric := coalesce(p_discount_amount,0);
  v_shipping numeric := coalesce(p_shipping_amount,0);
  v_paid numeric := coalesce(p_paid_amount,0);
  v_reason text;
begin
  if not (select public.is_admin()) then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if p_supplier_id is null or not exists (
    select 1 from public.inventory_suppliers where id = p_supplier_id and is_active
  ) then
    raise exception 'Supplier is missing or inactive' using errcode = '22023';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'At least one purchase item is required' using errcode = '22023';
  end if;
  if v_discount < 0 or v_shipping < 0 or v_paid < 0 then
    raise exception 'Purchase amounts cannot be negative' using errcode = '22023';
  end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_material_id := (v_item->>'material_id')::uuid;
    v_entered_qty := (v_item->>'quantity')::numeric;
    v_entered_cost := (v_item->>'unit_cost')::numeric;
    select unit into v_stock_unit
      from public.inventory_materials
      where id = v_material_id and is_active = true;
    if not found then
      raise exception 'Unknown or inactive inventory material' using errcode = '22023';
    end if;

    v_entered_unit := coalesce(nullif(v_item->>'purchase_unit',''), v_stock_unit);
    v_entered_factor := case v_entered_unit
      when 'g' then 1 when 'kg' then 1000
      when 'ml' then 1 when 'l' then 1000
      when 'unit' then 1 else null end;
    v_stock_factor := case v_stock_unit
      when 'g' then 1 when 'kg' then 1000
      when 'ml' then 1 when 'l' then 1000
      when 'unit' then 1 else null end;

    if v_entered_factor is null or v_stock_factor is null then
      if v_entered_unit <> v_stock_unit then
        raise exception 'Unit conversion is only supported for g/kg, ml/l and identical units; pack/box need a defined conversion.'
          using errcode = '22023';
      end if;
      v_entered_factor := 1;
      v_stock_factor := 1;
    end if;
    if (v_entered_unit in ('g','kg') and v_stock_unit not in ('g','kg'))
      or (v_entered_unit in ('ml','l') and v_stock_unit not in ('ml','l'))
      or (v_entered_unit = 'unit' and v_stock_unit <> 'unit')
      or (v_entered_unit not in ('g','kg','ml','l','unit') and v_entered_unit <> v_stock_unit) then
      raise exception 'Incompatible purchase unit % for stock unit %', v_entered_unit, v_stock_unit
        using errcode = '22023';
    end if;
    if v_entered_qty is null or v_entered_qty <= 0 or v_entered_cost is null or v_entered_cost < 0 then
      raise exception 'Invalid quantity or unit cost' using errcode = '22023';
    end if;

    v_ratio := v_entered_factor / v_stock_factor;
    v_quantity := round(v_entered_qty * v_ratio, 3);
    if v_quantity <= 0 then
      raise exception 'Quantity is below stock-unit precision; increase precision or enter a larger quantity.'
        using errcode = '22023';
    end if;
    v_subtotal := v_subtotal + round(v_entered_qty * v_entered_cost, 2);
  end loop;

  if v_discount > v_subtotal then
    raise exception 'Invoice discount cannot exceed the item subtotal' using errcode = '22023';
  end if;
  v_total := greatest(0, v_subtotal - v_discount + v_shipping);
  if v_paid > v_total then
    raise exception 'Paid amount cannot exceed purchase total' using errcode = '22023';
  end if;
  if v_subtotal > 0 then
    v_cost_factor := v_total / v_subtotal;
  end if;

  insert into public.inventory_purchases(
    supplier_id, invoice_number, purchase_date, subtotal, discount_amount,
    shipping_amount, total_amount, paid_amount, payment_status, notes, created_by
  ) values (
    p_supplier_id, coalesce(trim(p_invoice_number),''), coalesce(p_purchase_date,current_date),
    v_subtotal, v_discount, v_shipping, v_total, v_paid,
    case when v_total = 0 or v_paid >= v_total then 'paid'
         when v_paid = 0 then 'unpaid' else 'partial' end,
    coalesce(p_notes,''), (select auth.uid())
  ) returning id into v_purchase_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_material_id := (v_item->>'material_id')::uuid;
    v_entered_qty := (v_item->>'quantity')::numeric;
    v_entered_cost := (v_item->>'unit_cost')::numeric;
    select unit into v_stock_unit
      from public.inventory_materials
      where id = v_material_id and is_active = true;
    v_entered_unit := coalesce(nullif(v_item->>'purchase_unit',''), v_stock_unit);
    v_entered_factor := case v_entered_unit
      when 'g' then 1 when 'kg' then 1000
      when 'ml' then 1 when 'l' then 1000
      when 'unit' then 1 else 1 end;
    v_stock_factor := case v_stock_unit
      when 'g' then 1 when 'kg' then 1000
      when 'ml' then 1 when 'l' then 1000
      when 'unit' then 1 else 1 end;
    v_ratio := v_entered_factor / v_stock_factor;
    v_quantity := round(v_entered_qty * v_ratio, 3);
    if v_subtotal > 0 then
      v_unit_cost := round((v_entered_cost / v_ratio) * v_cost_factor, 2);
    else
      v_unit_cost := round(v_entered_cost / v_ratio, 2);
    end if;

    insert into public.inventory_purchase_items(
      purchase_id, material_id, quantity, unit_cost,
      entered_quantity, entered_unit, conversion_factor, entered_unit_cost
    ) values (
      v_purchase_id, v_material_id, v_quantity, v_unit_cost,
      v_entered_qty, v_entered_unit, v_ratio, v_entered_cost
    );

    v_reason := 'خرید تأمین‌کننده؛ سند ' ||
      coalesce(nullif(trim(p_invoice_number),''), v_purchase_id::text);
    perform public.admin_receive_inventory(v_material_id, v_quantity, v_unit_cost, v_reason);
  end loop;
  return v_purchase_id;
end;
$$;

revoke all on function public.admin_record_inventory_purchase(uuid,text,date,jsonb,numeric,numeric,numeric,text) from public, anon;
grant execute on function public.admin_record_inventory_purchase(uuid,text,date,jsonb,numeric,numeric,numeric,text) to authenticated;

commit;
