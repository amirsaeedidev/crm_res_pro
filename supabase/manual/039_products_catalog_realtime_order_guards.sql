-- Applied migration: products_catalog_realtime_and_order_guards
-- Product metadata is public catalog data. Realtime needs to observe transitions
-- to inactive/unavailable, while customer UI filters inactive products locally.

alter table public.products
  add column if not exists sort_order integer not null default 0,
  add column if not exists is_discount_active boolean not null default true;

update public.products
set is_discount_active = (discount_percent > 0)
where is_discount_active is distinct from (discount_percent > 0);

alter table public.products
  drop constraint if exists products_sort_order_nonnegative;
alter table public.products
  add constraint products_sort_order_nonnegative check (sort_order >= 0) not valid;
alter table public.products
  validate constraint products_sort_order_nonnegative;

create index if not exists products_active_category_sort_idx
  on public.products (is_active, category_id, sort_order, created_at desc);

drop policy if exists products_select_anon on public.products;
drop policy if exists products_select_auth on public.products;
drop policy if exists products_select_public_catalog on public.products;

create policy products_select_public_catalog
  on public.products for select to anon, authenticated using (true);

create or replace function public.validate_order_item_product()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.products p
    where p.id = new.product_id and p.is_active = true and p.is_available = true
  ) then
    raise exception 'محصول غیرفعال است یا در حال حاضر موجود نیست.' using errcode = '22023';
  end if;
  return new;
end;
$$;

drop trigger if exists validate_order_item_product_before_insert on public.order_items;
create trigger validate_order_item_product_before_insert
before insert on public.order_items
for each row execute function public.validate_order_item_product();

-- Verified live transactional order RPC definition after migration.
CREATE OR REPLACE FUNCTION public.place_order(p_order_type text, p_items jsonb, p_address_id uuid DEFAULT NULL::uuid, p_address_line text DEFAULT NULL::text, p_table_number integer DEFAULT NULL::integer, p_table_id uuid DEFAULT NULL::uuid, p_note text DEFAULT NULL::text, p_discount_code text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_order_id uuid;
  v_subtotal numeric := 0;
  v_discount numeric := 0;
  v_delivery_fee numeric := 0;
  v_configured_delivery_fee numeric := 0;
  v_min_delivery_amount numeric := 0;
  v_total numeric := 0;
  v_item jsonb;
  v_product_id uuid;
  v_qty integer;
  v_price numeric;
  v_discount_row public.discounts%rowtype;
  v_stock record;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if p_order_type not in ('delivery','pickup','dine_in') then raise exception 'Invalid order type' using errcode='22023'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Order must contain at least one item' using errcode='22023'; end if;
  if p_order_type='delivery' and nullif(trim(coalesce(p_address_line,'')),'') is null and p_address_id is null then raise exception 'Delivery address is required' using errcode='22023'; end if;
  if p_order_type='dine_in' and (p_table_number is null or p_table_id is null) then raise exception 'A valid table must be selected for dine-in orders' using errcode='22023'; end if;
  if p_table_id is not null and not exists(select 1 from public.restaurant_tables rt where rt.id=p_table_id and rt.table_number=p_table_number and rt.is_active=true) then raise exception 'Invalid or inactive table' using errcode='22023'; end if;
  if p_address_id is not null and not exists(select 1 from public.addresses a where a.id=p_address_id and a.user_id=v_user_id) then raise exception 'Invalid address' using errcode='22023'; end if;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::integer;
    if v_qty is null or v_qty<=0 or v_qty>100 then raise exception 'Invalid quantity' using errcode='22023'; end if;

    select
      case when p.is_discount_active and p.discount_percent>0
        then p.discounted_price else p.price end
    into v_price
    from public.products p
    where p.id=v_product_id and p.is_active=true and p.is_available=true
    for share;

    if v_price is null then
      raise exception 'محصول غیرفعال است یا در حال حاضر موجود نیست: %',v_product_id using errcode='22023';
    end if;
    v_subtotal := v_subtotal + v_price*v_qty;
  end loop;

  for v_stock in
    select m.id,m.name,m.quantity_on_hand,sum(r.quantity_per_product*(i.value->>'quantity')::integer)::numeric(14,3) required
    from jsonb_array_elements(p_items) i(value)
    join public.product_recipes r on r.product_id=(i.value->>'product_id')::uuid
    join public.inventory_materials m on m.id=r.material_id and m.is_active=true
    group by m.id,m.name,m.quantity_on_hand
    order by m.id
  loop
    if v_stock.quantity_on_hand < v_stock.required then
      raise exception 'موجودی ماده اولیه «%» کافی نیست. موجود: %، موردنیاز: %',v_stock.name,v_stock.quantity_on_hand,v_stock.required using errcode='22023';
    end if;
  end loop;

  if p_order_type='delivery' then
    select coalesce(s.min_delivery_amount,0),coalesce(s.fixed_delivery_fee,0)
    into v_min_delivery_amount,v_configured_delivery_fee
    from public.restaurant_settings s where s.id='restaurant';
    v_min_delivery_amount:=coalesce(v_min_delivery_amount,0);
    v_configured_delivery_fee:=coalesce(v_configured_delivery_fee,0);
    if v_subtotal<v_min_delivery_amount then raise exception 'Minimum delivery order is %',v_min_delivery_amount using errcode='22023'; end if;
    v_delivery_fee:=greatest(v_configured_delivery_fee,0);
  end if;

  if nullif(trim(coalesce(p_discount_code,'')),'') is not null then
    select d.* into v_discount_row from public.discounts d
    where upper(d.code)=upper(trim(p_discount_code)) and d.is_active=true
      and (d.starts_at is null or d.starts_at<=now())
      and (d.expires_at is null or d.expires_at>now())
      and v_subtotal>=d.min_order_amount
      and (d.usage_limit is null or d.used_count<d.usage_limit)
      and (d.restricted_to_customers=false or exists(select 1 from public.discount_customer_targets t where t.discount_id=d.id and t.user_id=v_user_id))
      and (d.per_user_usage_limit is null or
        (select count(*) from public.orders eo where eo.user_id=v_user_id and upper(coalesce(eo.discount_code,''))=upper(d.code) and eo.status<>'cancelled')<d.per_user_usage_limit)
    for update;
    if not found then raise exception 'Invalid, expired, or ineligible discount code' using errcode='22023'; end if;
    if v_discount_row.discount_type='percent' then v_discount:=round(v_subtotal*(v_discount_row.discount_value/100),0);
    else v_discount:=v_discount_row.discount_value; end if;
    if v_discount_row.max_discount_amount is not null then v_discount:=least(v_discount,v_discount_row.max_discount_amount); end if;
    v_discount:=least(greatest(v_discount,0),v_subtotal);
  end if;

  v_total:=v_subtotal-v_discount+v_delivery_fee;
  insert into public.orders(user_id,address_id,address_line,table_number,table_id,order_type,status,subtotal_amount,discount_code,discount_amount,delivery_fee,total_amount,note)
  values(v_user_id,p_address_id,p_address_line,p_table_number,p_table_id,p_order_type,'pending',v_subtotal,nullif(trim(p_discount_code),''),v_discount,v_delivery_fee,v_total,p_note)
  returning id into v_order_id;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_product_id:=(v_item->>'product_id')::uuid;
    v_qty:=(v_item->>'quantity')::integer;
    select case when p.is_discount_active and p.discount_percent>0
      then p.discounted_price else p.price end
    into v_price
    from public.products p
    where p.id=v_product_id and p.is_active=true and p.is_available=true
    for share;
    if v_price is null then
      raise exception 'محصول غیرفعال است یا در حال حاضر موجود نیست: %',v_product_id using errcode='22023';
    end if;
    insert into public.order_items(order_id,product_id,quantity,unit_price,total_price)
    values(v_order_id,v_product_id,v_qty,v_price,v_price*v_qty);
  end loop;

  if v_discount_row.id is not null then
    update public.discounts set used_count=used_count+1,updated_at=now() where id=v_discount_row.id;
  end if;
  return v_order_id;
end;
$function$
;
