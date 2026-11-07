-- Phase 6: immutable order-item product-name snapshots.
-- Loyalty earning already runs atomically from category.loyalty_points_per_item
-- when an order transitions to completed; the customer app must not award points.

begin;

alter table public.order_items
  add column if not exists product_name text;

-- Best-effort backfill for historical orders. Old names cannot be reconstructed
-- if a product was renamed before this migration.
update public.order_items oi
set product_name = coalesce(nullif(pg_catalog.btrim(p.name), ''), 'محصول حذف‌شده')
from public.products p
where p.id = oi.product_id
  and nullif(pg_catalog.btrim(coalesce(oi.product_name, '')), '') is null;

update public.order_items
set product_name = 'محصول حذف‌شده'
where nullif(pg_catalog.btrim(coalesce(product_name, '')), '') is null;

alter table public.order_items
  alter column product_name set default '',
  alter column product_name set not null;

-- Protect all insertion paths, including any legacy/admin writers.
create or replace function public.set_order_item_product_name_snapshot()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if nullif(pg_catalog.btrim(coalesce(new.product_name, '')), '') is null then
    select p.name into new.product_name
    from public.products p
    where p.id = new.product_id;
    new.product_name := coalesce(nullif(pg_catalog.btrim(new.product_name), ''), 'محصول حذف‌شده');
  end if;
  return new;
end;
$function$;

drop trigger if exists set_order_item_product_name_snapshot on public.order_items;
create trigger set_order_item_product_name_snapshot
before insert or update of product_id, product_name on public.order_items
for each row execute function public.set_order_item_product_name_snapshot();

-- The transactional checkout RPC captures the product name and payable price
-- while it holds the product row lock. The client never supplies either value.
do $migration$
declare
  v_definition text;
  v_old_declaration text := '  v_price numeric;';
  v_new_declaration text := '  v_price numeric;
  v_product_name text;';
  v_old_block text := 'select case when p.is_discount_active and p.discount_percent>0 then p.discounted_price else p.price end
      into v_price from public.products p where p.id=v_product_id and p.is_active=true and p.is_available=true for share;
    if v_price is null then raise exception ''Product is unavailable: %'',v_product_id using errcode=''22023''; end if;
    insert into public.order_items(order_id,product_id,quantity,unit_price,total_price)
      values(v_order_id,v_product_id,v_qty,v_price,v_price*v_qty);';
  v_new_block text := 'select p.name, case when p.is_discount_active and p.discount_percent>0 then p.discounted_price else p.price end
      into v_product_name, v_price from public.products p where p.id=v_product_id and p.is_active=true and p.is_available=true for share;
    if v_price is null then raise exception ''Product is unavailable: %'',v_product_id using errcode=''22023''; end if;
    insert into public.order_items(order_id,product_id,product_name,quantity,unit_price,total_price)
      values(v_order_id,v_product_id,v_product_name,v_qty,v_price,v_price*v_qty);';
begin
  select pg_catalog.pg_get_functiondef(
    'public.place_order_idempotent(uuid,text,jsonb,uuid,text,integer,uuid,text,text)'::regprocedure
  ) into v_definition;

  if pg_catalog.strpos(v_definition, v_old_declaration) = 0 then
    raise exception 'Could not locate checkout RPC declaration; migration stopped safely.';
  end if;
  if pg_catalog.strpos(v_definition, v_old_block) = 0 then
    raise exception 'Could not locate checkout RPC order-item insert block; migration stopped safely.';
  end if;

  v_definition := pg_catalog.replace(v_definition, v_old_declaration, v_new_declaration);
  v_definition := pg_catalog.replace(v_definition, v_old_block, v_new_block);
  execute v_definition;
end;
$migration$;

commit;
