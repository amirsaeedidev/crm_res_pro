-- Menu availability and recipe-based ingredient validation at checkout.
begin;

alter table public.products
  add column if not exists is_available boolean not null default true,
  add column if not exists unavailable_reason text not null default '';

create index if not exists products_available_active_idx
  on public.products(is_active,is_available);

alter table public.product_recipes enable row level security;
drop policy if exists product_recipes_admin_all on public.product_recipes;
create policy product_recipes_admin_all on public.product_recipes
for all to authenticated
using ((select public.is_admin()))
with check ((select public.is_admin()));
grant select,insert,update,delete on public.product_recipes to authenticated;

-- A product may be ordered only if manually available and all recipe ingredients
-- can cover the complete basket. This check is done inside the database transaction.
create or replace function public.place_order(
 p_order_type text,
 p_items jsonb,
 p_address_id uuid default null,
 p_address_line text default null,
 p_table_number integer default null,
 p_table_id uuid default null,
 p_note text default null,
 p_discount_code text default null
) returns uuid
language plpgsql security definer set search_path = '' as $function$
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
   select case when p.discount_percent>0 then p.discounted_price else p.price end
     into v_price from public.products p
     where p.id=v_product_id and p.is_active=true and p.is_available=true;
   if v_price is null then raise exception 'غذا غیرفعال است یا در حال حاضر موجود نیست: %',v_product_id using errcode='22023'; end if;
   v_subtotal := v_subtotal + v_price*v_qty;
 end loop;

 -- Aggregate all ingredients across the whole basket, avoiding over-selling a
 -- shared ingredient when several different foods use the same material.
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
   select case when p.discount_percent>0 then p.discounted_price else p.price end
   into v_price from public.products p where p.id=v_product_id and p.is_active=true and p.is_available=true;
   insert into public.order_items(order_id,product_id,quantity,unit_price,total_price)
   values(v_order_id,v_product_id,v_qty,v_price,v_price*v_qty);
 end loop;
 if v_discount_row.id is not null then
   update public.discounts set used_count=used_count+1,updated_at=now() where id=v_discount_row.id;
 end if;
 return v_order_id;
end;
$function$;

revoke all on function public.place_order(text,jsonb,uuid,text,integer,uuid,text,text) from public,anon;
grant execute on function public.place_order(text,jsonb,uuid,text,integer,uuid,text,text) to authenticated;
commit;
