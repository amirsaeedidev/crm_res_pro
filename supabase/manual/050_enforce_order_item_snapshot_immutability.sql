-- Keep the order-time product identity and unit price immutable after insertion.
create or replace function public.set_order_item_product_name_snapshot()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if tg_op = 'INSERT' then
    select p.name into new.product_name
    from public.products p
    where p.id = new.product_id;
    new.product_name := coalesce(nullif(pg_catalog.btrim(new.product_name), ''), 'محصول حذف‌شده');
  else
    -- Historical item identity and price are snapshots, not live product fields.
    new.product_id := old.product_id;
    new.product_name := old.product_name;
    new.unit_price := old.unit_price;
    new.total_price := old.unit_price * new.quantity;
  end if;
  return new;
end;
$function$;

drop trigger if exists set_order_item_product_name_snapshot on public.order_items;
create trigger set_order_item_product_name_snapshot
before insert or update of product_id, product_name, unit_price, total_price, quantity
on public.order_items
for each row execute function public.set_order_item_product_name_snapshot();
