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

-- The live place_order function was replaced without changing its signature.
-- It now reads price from locked, active and available product rows, applies
-- discount only when is_discount_active=true, and retains the existing recipe,
-- delivery, discount-code and order-item transaction logic.
