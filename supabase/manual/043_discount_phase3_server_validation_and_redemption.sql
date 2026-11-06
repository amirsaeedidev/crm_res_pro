-- Phase 3: discount scopes, server-side quotes, idempotent order creation,
-- redemption history, cancellation release, customer visibility and DB clock.
-- Applied to Supabase project cfdzxtnkiptnlitwvnla on 2026-11-06.

alter table public.discounts
  add column if not exists allow_with_product_discount boolean not null default false;
alter table public.orders
  add column if not exists client_request_id uuid;
create unique index if not exists orders_user_client_request_uidx
  on public.orders(user_id, client_request_id)
  where client_request_id is not null;

create table if not exists public.discount_product_targets (
  discount_id uuid not null references public.discounts(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  created_at timestamptz not null default pg_catalog.now(),
  primary key (discount_id, product_id)
);
create table if not exists public.discount_category_targets (
  discount_id uuid not null references public.discounts(id) on delete cascade,
  category_id uuid not null references public.categories(id) on delete cascade,
  created_at timestamptz not null default pg_catalog.now(),
  primary key (discount_id, category_id)
);
create table if not exists public.discount_redemptions (
  id uuid primary key default gen_random_uuid(),
  discount_id uuid not null references public.discounts(id) on delete restrict,
  order_id uuid not null unique references public.orders(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  code_snapshot text not null,
  discount_amount numeric not null check (discount_amount >= 0),
  status text not null default 'redeemed' check (status in ('redeemed','released')),
  redeemed_at timestamptz not null default pg_catalog.now(),
  released_at timestamptz
);
create index if not exists discount_redemptions_discount_user_status_idx
  on public.discount_redemptions(discount_id, user_id, status);

alter table public.discount_product_targets enable row level security;
alter table public.discount_category_targets enable row level security;
alter table public.discount_redemptions enable row level security;

drop policy if exists discount_product_targets_admin_all on public.discount_product_targets;
create policy discount_product_targets_admin_all on public.discount_product_targets
  for all to authenticated using ((select public.is_admin()))
  with check ((select public.is_admin()));
drop policy if exists discount_category_targets_admin_all on public.discount_category_targets;
create policy discount_category_targets_admin_all on public.discount_category_targets
  for all to authenticated using ((select public.is_admin()))
  with check ((select public.is_admin()));
drop policy if exists discount_redemptions_admin_select on public.discount_redemptions;
create policy discount_redemptions_admin_select on public.discount_redemptions
  for select to authenticated using ((select public.is_admin()));
drop policy if exists discount_redemptions_owner_select on public.discount_redemptions;
create policy discount_redemptions_owner_select on public.discount_redemptions
  for select to authenticated using (user_id = (select auth.uid()));
grant select, insert, update, delete on public.discount_product_targets to authenticated;
grant select, insert, update, delete on public.discount_category_targets to authenticated;
grant select on public.discount_redemptions to authenticated;
revoke all on public.discount_redemptions from anon;

create or replace function public.quote_discount_code(p_code text, p_items jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_discount public.discounts%rowtype;
  v_item jsonb;
  v_product public.products%rowtype;
  v_qty integer;
  v_price numeric;
  v_subtotal numeric := 0;
  v_eligible_subtotal numeric := 0;
  v_amount numeric := 0;
  v_has_scope boolean := false;
  v_is_targeted boolean := false;
  v_now timestamptz := pg_catalog.now();
begin
  if v_user_id is null then return jsonb_build_object('success',false,'message','برای اعمال تخفیف ابتدا وارد حساب شوید.'); end if;
  if pg_catalog.upper(pg_catalog.btrim(coalesce(p_code,''))) = '' then return jsonb_build_object('success',false,'message','کد تخفیف را وارد کنید.'); end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then return jsonb_build_object('success',false,'message','سبد خرید خالی است.'); end if;
  select d.* into v_discount from public.discounts d
    where pg_catalog.upper(d.code)=pg_catalog.upper(pg_catalog.btrim(p_code)) limit 1;
  if not found then return jsonb_build_object('success',false,'message','کد تخفیف معتبر نیست.'); end if;
  if not v_discount.is_active then return jsonb_build_object('success',false,'message','این کد تخفیف غیرفعال است.'); end if;
  if v_discount.starts_at is not null and v_discount.starts_at > v_now then return jsonb_build_object('success',false,'message','زمان شروع این تخفیف هنوز نرسیده است.'); end if;
  if v_discount.expires_at is not null and v_discount.expires_at <= v_now then return jsonb_build_object('success',false,'message','مهلت استفاده از این کد تمام شده است.'); end if;
  if v_discount.usage_limit is not null and v_discount.used_count >= v_discount.usage_limit then return jsonb_build_object('success',false,'message','ظرفیت استفاده از این کد تکمیل شده است.'); end if;
  if v_discount.restricted_to_customers and not exists (
    select 1 from public.discount_customer_targets t where t.discount_id=v_discount.id and t.user_id=v_user_id
  ) then return jsonb_build_object('success',false,'message','این تخفیف برای حساب شما فعال نیست.'); end if;
  if v_discount.per_user_usage_limit is not null and (
    select count(*) from public.orders o where o.user_id=v_user_id
      and pg_catalog.upper(coalesce(o.discount_code,''))=pg_catalog.upper(v_discount.code)
      and o.status <> 'cancelled'
  ) >= v_discount.per_user_usage_limit then
    return jsonb_build_object('success',false,'message','سقف استفاده شما از این کد تکمیل شده است.');
  end if;
  select exists(select 1 from public.discount_product_targets t where t.discount_id=v_discount.id)
      or exists(select 1 from public.discount_category_targets t where t.discount_id=v_discount.id)
    into v_has_scope;
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'quantity')::integer;
    if v_qty is null or v_qty <= 0 or v_qty > 100 then return jsonb_build_object('success',false,'message','تعداد یکی از محصولات معتبر نیست.'); end if;
    select p.* into v_product from public.products p
      where p.id=(v_item->>'product_id')::uuid and p.is_active=true and p.is_available=true;
    if not found then return jsonb_build_object('success',false,'message','یکی از محصولات دیگر در دسترس نیست.'); end if;
    v_price := case when v_product.is_discount_active and v_product.discount_percent>0 then v_product.discounted_price else v_product.price end;
    v_subtotal := v_subtotal + v_price*v_qty;
    v_is_targeted := not v_has_scope
      or exists(select 1 from public.discount_product_targets t where t.discount_id=v_discount.id and t.product_id=v_product.id)
      or exists(select 1 from public.discount_category_targets t where t.discount_id=v_discount.id and t.category_id=v_product.category_id);
    if v_is_targeted and (v_discount.allow_with_product_discount or not (v_product.is_discount_active and v_product.discount_percent>0)) then
      v_eligible_subtotal := v_eligible_subtotal + v_price*v_qty;
    end if;
  end loop;
  if v_subtotal < v_discount.min_order_amount then return jsonb_build_object('success',false,'message','حداقل مبلغ سفارش برای این کد رعایت نشده است.','min_order_amount',v_discount.min_order_amount); end if;
  if v_eligible_subtotal <= 0 then return jsonb_build_object('success',false,'message','این کد شامل محصولات سبد خرید شما نمی‌شود.'); end if;
  if v_discount.discount_type='percent' then v_amount := pg_catalog.round(v_eligible_subtotal*v_discount.discount_value/100,0);
  else v_amount := v_discount.discount_value; end if;
  if v_discount.max_discount_amount is not null then v_amount := least(v_amount,v_discount.max_discount_amount); end if;
  v_amount := least(greatest(v_amount,0),v_eligible_subtotal);
  return jsonb_build_object('success',true,'message','کد تخفیف قابل استفاده است.','discount_id',v_discount.id,
    'code',v_discount.code,'title',v_discount.title,'description',coalesce(v_discount.description,''),
    'discount_type',v_discount.discount_type,'discount_value',v_discount.discount_value,
    'min_order_amount',v_discount.min_order_amount,'max_discount_amount',v_discount.max_discount_amount,
    'starts_at',v_discount.starts_at,'expires_at',v_discount.expires_at,'is_active',v_discount.is_active,
    'discount_amount',v_amount,'eligible_subtotal',v_eligible_subtotal);
end;
$function$;

create or replace function public.place_order_idempotent(
  p_client_request_id uuid, p_order_type text, p_items jsonb,
  p_address_id uuid default null, p_address_line text default null,
  p_table_number integer default null, p_table_id uuid default null,
  p_note text default null, p_discount_code text default null
) returns uuid language plpgsql security definer set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_existing_order_id uuid;
  v_order_id uuid;
  v_subtotal numeric := 0;
  v_eligible_subtotal numeric := 0;
  v_discount numeric := 0;
  v_delivery_fee numeric := 0;
  v_configured_delivery_fee numeric := 0;
  v_min_delivery_amount numeric := 0;
  v_total numeric := 0;
  v_item jsonb;
  v_product_id uuid;
  v_qty integer;
  v_price numeric;
  v_product public.products%rowtype;
  v_discount_row public.discounts%rowtype;
  v_has_scope boolean := false;
  v_is_targeted boolean := false;
  v_stock record;
  v_now timestamptz := pg_catalog.now();
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if p_client_request_id is null then raise exception 'Client request id is required' using errcode='22023'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user_id::text || ':' || p_client_request_id::text,0));
  select o.id into v_existing_order_id from public.orders o where o.user_id=v_user_id and o.client_request_id=p_client_request_id;
  if found then return v_existing_order_id; end if;
  if p_order_type not in ('delivery','pickup','dine_in') then raise exception 'Invalid order type' using errcode='22023'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Order must contain at least one item' using errcode='22023'; end if;
  if p_order_type='delivery' and nullif(pg_catalog.btrim(coalesce(p_address_line,'')),'') is null and p_address_id is null then raise exception 'Delivery address is required' using errcode='22023'; end if;
  if p_order_type='dine_in' and (p_table_number is null or p_table_id is null) then raise exception 'A valid table must be selected for dine-in orders' using errcode='22023'; end if;
  if p_table_id is not null and not exists(select 1 from public.restaurant_tables rt where rt.id=p_table_id and rt.table_number=p_table_number and rt.is_active=true) then raise exception 'Invalid or inactive table' using errcode='22023'; end if;
  if p_address_id is not null and not exists(select 1 from public.addresses a where a.id=p_address_id and a.user_id=v_user_id) then raise exception 'Invalid address' using errcode='22023'; end if;
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::integer;
    if v_qty is null or v_qty<=0 or v_qty>100 then raise exception 'Invalid quantity' using errcode='22023'; end if;
    select p.* into v_product from public.products p where p.id=v_product_id and p.is_active=true and p.is_available=true for share;
    if not found then raise exception 'Product is unavailable: %',v_product_id using errcode='22023'; end if;
    v_price := case when v_product.is_discount_active and v_product.discount_percent>0 then v_product.discounted_price else v_product.price end;
    v_subtotal := v_subtotal + v_price*v_qty;
  end loop;
  for v_stock in
    select m.id,m.name,m.quantity_on_hand,sum(r.quantity_per_product*(i.value->>'quantity')::integer)::numeric(14,3) required
    from jsonb_array_elements(p_items) i(value)
    join public.product_recipes r on r.product_id=(i.value->>'product_id')::uuid
    join public.inventory_materials m on m.id=r.material_id and m.is_active=true
    group by m.id,m.name,m.quantity_on_hand order by m.id
  loop
    if v_stock.quantity_on_hand < v_stock.required then raise exception 'Insufficient stock for material %',v_stock.name using errcode='22023'; end if;
  end loop;
  if p_order_type='delivery' then
    select coalesce(s.min_delivery_amount,0),coalesce(s.fixed_delivery_fee,0)
      into v_min_delivery_amount,v_configured_delivery_fee from public.restaurant_settings s where s.id='restaurant';
    v_min_delivery_amount:=coalesce(v_min_delivery_amount,0);
    v_configured_delivery_fee:=coalesce(v_configured_delivery_fee,0);
    if v_subtotal<v_min_delivery_amount then raise exception 'Minimum delivery order is %',v_min_delivery_amount using errcode='22023'; end if;
    v_delivery_fee:=greatest(v_configured_delivery_fee,0);
  end if;
  if nullif(pg_catalog.btrim(coalesce(p_discount_code,'')),'') is not null then
    select d.* into v_discount_row from public.discounts d
      where pg_catalog.upper(d.code)=pg_catalog.upper(pg_catalog.btrim(p_discount_code)) for update;
    if not found then raise exception 'Invalid, expired, or ineligible discount code' using errcode='22023'; end if;
    if not v_discount_row.is_active
      or (v_discount_row.starts_at is not null and v_discount_row.starts_at>v_now)
      or (v_discount_row.expires_at is not null and v_discount_row.expires_at<=v_now)
      or v_subtotal<v_discount_row.min_order_amount
      or (v_discount_row.usage_limit is not null and v_discount_row.used_count>=v_discount_row.usage_limit)
      or (v_discount_row.restricted_to_customers and not exists(select 1 from public.discount_customer_targets t where t.discount_id=v_discount_row.id and t.user_id=v_user_id))
      or (v_discount_row.per_user_usage_limit is not null and
        (select count(*) from public.orders o where o.user_id=v_user_id and pg_catalog.upper(coalesce(o.discount_code,''))=pg_catalog.upper(v_discount_row.code) and o.status<>'cancelled')>=v_discount_row.per_user_usage_limit)
    then raise exception 'Invalid, expired, or ineligible discount code' using errcode='22023'; end if;
    select exists(select 1 from public.discount_product_targets t where t.discount_id=v_discount_row.id)
        or exists(select 1 from public.discount_category_targets t where t.discount_id=v_discount_row.id)
      into v_has_scope;
    for v_item in select value from jsonb_array_elements(p_items) loop
      v_product_id:=(v_item->>'product_id')::uuid;
      v_qty:=(v_item->>'quantity')::integer;
      select p.* into v_product from public.products p where p.id=v_product_id and p.is_active=true and p.is_available=true;
      v_price:=case when v_product.is_discount_active and v_product.discount_percent>0 then v_product.discounted_price else v_product.price end;
      v_is_targeted:=not v_has_scope
        or exists(select 1 from public.discount_product_targets t where t.discount_id=v_discount_row.id and t.product_id=v_product.id)
        or exists(select 1 from public.discount_category_targets t where t.discount_id=v_discount_row.id and t.category_id=v_product.category_id);
      if v_is_targeted and (v_discount_row.allow_with_product_discount or not (v_product.is_discount_active and v_product.discount_percent>0)) then
        v_eligible_subtotal:=v_eligible_subtotal+v_price*v_qty;
      end if;
    end loop;
    if v_eligible_subtotal<=0 then raise exception 'Discount does not apply to any cart item' using errcode='22023'; end if;
    if v_discount_row.discount_type='percent' then v_discount:=pg_catalog.round(v_eligible_subtotal*v_discount_row.discount_value/100,0);
    else v_discount:=v_discount_row.discount_value; end if;
    if v_discount_row.max_discount_amount is not null then v_discount:=least(v_discount,v_discount_row.max_discount_amount); end if;
    v_discount:=least(greatest(v_discount,0),v_eligible_subtotal);
  end if;
  v_total:=v_subtotal-v_discount+v_delivery_fee;
  insert into public.orders(user_id,client_request_id,address_id,address_line,table_number,table_id,order_type,status,subtotal_amount,discount_code,discount_amount,delivery_fee,total_amount,note)
  values(v_user_id,p_client_request_id,p_address_id,p_address_line,p_table_number,p_table_id,p_order_type,'pending',v_subtotal,nullif(pg_catalog.btrim(p_discount_code),''),v_discount,v_delivery_fee,v_total,p_note)
  returning id into v_order_id;
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_product_id:=(v_item->>'product_id')::uuid;
    v_qty:=(v_item->>'quantity')::integer;
    select case when p.is_discount_active and p.discount_percent>0 then p.discounted_price else p.price end
      into v_price from public.products p where p.id=v_product_id and p.is_active=true and p.is_available=true for share;
    if v_price is null then raise exception 'Product is unavailable: %',v_product_id using errcode='22023'; end if;
    insert into public.order_items(order_id,product_id,quantity,unit_price,total_price) values(v_order_id,v_product_id,v_qty,v_price,v_price*v_qty);
  end loop;
  if v_discount_row.id is not null then
    update public.discounts set used_count=used_count+1,updated_at=v_now where id=v_discount_row.id;
    insert into public.discount_redemptions(discount_id,order_id,user_id,code_snapshot,discount_amount)
      values(v_discount_row.id,v_order_id,v_user_id,v_discount_row.code,v_discount);
  end if;
  return v_order_id;
end;
$function$;

create or replace function public.release_discount_redemption_on_cancel()
returns trigger language plpgsql security definer set search_path = ''
as $function$
declare v_discount_id uuid;
begin
  if old.status is distinct from new.status and new.status='cancelled' then
    update public.discount_redemptions set status='released',released_at=pg_catalog.now()
      where order_id=new.id and status='redeemed' returning discount_id into v_discount_id;
    if v_discount_id is not null then
      update public.discounts set used_count=greatest(used_count-1,0),updated_at=pg_catalog.now() where id=v_discount_id;
    end if;
  end if;
  return new;
end;
$function$;
drop trigger if exists release_discount_redemption_on_cancel on public.orders;
create trigger release_discount_redemption_on_cancel after update of status on public.orders
for each row execute function public.release_discount_redemption_on_cancel();

create or replace function public.list_customer_discounts()
returns setof public.discounts language sql stable security definer set search_path = ''
as $function$
  select d.* from public.discounts d
  where auth.uid() is not null and d.is_active=true
    and (d.starts_at is null or d.starts_at<=pg_catalog.now())
    and (d.expires_at is null or d.expires_at>pg_catalog.now())
    and (d.usage_limit is null or d.used_count<d.usage_limit)
    and (not d.restricted_to_customers or exists(
      select 1 from public.discount_customer_targets t where t.discount_id=d.id and t.user_id=auth.uid()))
    and (d.per_user_usage_limit is null or (
      select count(*) from public.orders o where o.user_id=auth.uid()
      and pg_catalog.upper(coalesce(o.discount_code,''))=pg_catalog.upper(d.code) and o.status<>'cancelled'
    )<d.per_user_usage_limit)
  order by d.created_at desc;
$function$;

drop policy if exists discounts_select_anon on public.discounts;
drop policy if exists discounts_select_auth on public.discounts;
create policy discounts_select_anon on public.discounts for select to anon using (
  is_active=true and restricted_to_customers=false
  and (starts_at is null or starts_at<=pg_catalog.now())
  and (expires_at is null or expires_at>pg_catalog.now())
  and (usage_limit is null or used_count<usage_limit)
);
create policy discounts_select_auth on public.discounts for select to authenticated using (
  (select public.is_admin()) or (
    is_active=true
    and (starts_at is null or starts_at<=pg_catalog.now())
    and (expires_at is null or expires_at>pg_catalog.now())
    and (usage_limit is null or used_count<usage_limit)
    and (not restricted_to_customers or exists(
      select 1 from public.discount_customer_targets t where t.discount_id=discounts.id and t.user_id=(select auth.uid())))
    and (per_user_usage_limit is null or (
      select count(*) from public.orders o where o.user_id=(select auth.uid())
      and pg_catalog.upper(coalesce(o.discount_code,''))=pg_catalog.upper(discounts.code)
      and o.status<>'cancelled')<per_user_usage_limit)
  )
);
drop policy if exists discount_customer_targets_owner_select on public.discount_customer_targets;
create policy discount_customer_targets_owner_select on public.discount_customer_targets
  for select to authenticated using (user_id=(select auth.uid()));

create or replace function public.admin_sync_discount_scopes(p_discount_id uuid,p_product_ids uuid[],p_category_ids uuid[])
returns void language plpgsql security invoker set search_path = ''
as $function$
begin
  if auth.uid() is null or not (select public.is_admin()) then raise exception 'Admin access required' using errcode='42501'; end if;
  if not exists(select 1 from public.discounts d where d.id=p_discount_id) then raise exception 'Discount not found' using errcode='P0002'; end if;
  delete from public.discount_product_targets where discount_id=p_discount_id;
  delete from public.discount_category_targets where discount_id=p_discount_id;
  insert into public.discount_product_targets(discount_id,product_id)
    select p_discount_id,x from unnest(coalesce(p_product_ids,'{}'::uuid[])) x on conflict do nothing;
  insert into public.discount_category_targets(discount_id,category_id)
    select p_discount_id,x from unnest(coalesce(p_category_ids,'{}'::uuid[])) x on conflict do nothing;
end;
$function$;
create or replace function public.admin_get_database_time()
returns timestamptz language plpgsql stable security invoker set search_path = ''
as $function$
begin
  if auth.uid() is null or not (select public.is_admin()) then raise exception 'Admin access required' using errcode='42501'; end if;
  return pg_catalog.now();
end;
$function$;
create or replace function public.get_customer_server_time()
returns timestamptz language sql stable security invoker set search_path = ''
as $function$
  select case when auth.uid() is null then null else pg_catalog.now() end;
$function$;

revoke all on function public.quote_discount_code(text,jsonb) from public,anon;
grant execute on function public.quote_discount_code(text,jsonb) to authenticated;
revoke all on function public.place_order_idempotent(uuid,text,jsonb,uuid,text,integer,uuid,text,text) from public,anon;
grant execute on function public.place_order_idempotent(uuid,text,jsonb,uuid,text,integer,uuid,text,text) to authenticated;
revoke all on function public.list_customer_discounts() from public,anon;
grant execute on function public.list_customer_discounts() to authenticated;
revoke all on function public.admin_sync_discount_scopes(uuid,uuid[],uuid[]) from public,anon;
grant execute on function public.admin_sync_discount_scopes(uuid,uuid[],uuid[]) to authenticated;
revoke all on function public.admin_get_database_time() from public,anon;
grant execute on function public.admin_get_database_time() to authenticated;
revoke all on function public.get_customer_server_time() from public,anon;
grant execute on function public.get_customer_server_time() to authenticated;
revoke all on function public.release_discount_redemption_on_cancel() from public,anon,authenticated;


-- Backfill historical discount use from orders and reconcile the global counter.
insert into public.discount_redemptions
  (discount_id,order_id,user_id,code_snapshot,discount_amount,status,redeemed_at,released_at)
select d.id,o.id,o.user_id,d.code,coalesce(o.discount_amount,0),
       case when o.status='cancelled' then 'released' else 'redeemed' end,
       coalesce(o.created_at,pg_catalog.now()),
       case when o.status='cancelled' then coalesce(o.updated_at,o.created_at,pg_catalog.now()) else null end
from public.orders o
join public.discounts d on pg_catalog.upper(d.code)=pg_catalog.upper(o.discount_code)
where nullif(pg_catalog.btrim(coalesce(o.discount_code,'')),'') is not null
  and o.user_id is not null
on conflict (order_id) do nothing;

update public.discounts d
set used_count = (
  select count(*)::integer from public.discount_redemptions r
  where r.discount_id=d.id and r.status='redeemed'
), updated_at=pg_catalog.now();


-- Preserve the redemption ledger if an order deletion is attempted.
alter table public.discount_redemptions
  drop constraint if exists discount_redemptions_order_id_fkey;
alter table public.discount_redemptions
  add constraint discount_redemptions_order_id_fkey
  foreign key (order_id) references public.orders(id) on delete restrict;


-- Normalize all coupon codes so whitespace/case cannot create ambiguous matches.
create or replace function public.normalize_discount_code()
returns trigger language plpgsql set search_path = ''
as $function$
begin
  new.code := pg_catalog.upper(pg_catalog.btrim(coalesce(new.code,'')));
  if new.code = '' then raise exception 'Discount code cannot be empty' using errcode='23514'; end if;
  return new;
end;
$function$;
drop trigger if exists normalize_discount_code_before_write on public.discounts;
create trigger normalize_discount_code_before_write
before insert or update of code on public.discounts
for each row execute function public.normalize_discount_code();
update public.discounts set code=pg_catalog.upper(pg_catalog.btrim(code))
where code is distinct from pg_catalog.upper(pg_catalog.btrim(code));
