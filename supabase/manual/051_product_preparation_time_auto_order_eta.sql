-- Add a preparation duration to each menu item and derive order ETA from its items.
begin;

alter table public.products
  add column if not exists preparation_time_minutes integer not null default 15;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.products'::regclass
      and conname = 'products_preparation_time_minutes_check'
  ) then
    alter table public.products
      add constraint products_preparation_time_minutes_check
      check (preparation_time_minutes between 1 and 600);
  end if;
end;
$$;

create or replace function public.refresh_order_estimated_ready_minutes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order_id uuid;
begin
  if tg_op = 'DELETE' then
    v_order_id := old.order_id;
  else
    v_order_id := new.order_id;
  end if;

  update public.orders o
  set estimated_ready_minutes = (
        select case when count(*) = 0 then null
          else greatest(1, sum(coalesce(p.preparation_time_minutes, 15) * oi.quantity))::integer
        end
        from public.order_items oi
        left join public.products p on p.id = oi.product_id
        where oi.order_id = v_order_id
      ),
      updated_at = pg_catalog.now()
  where o.id = v_order_id;

  if tg_op = 'UPDATE' and old.order_id is distinct from new.order_id then
    update public.orders o
    set estimated_ready_minutes = (
          select case when count(*) = 0 then null
            else greatest(1, sum(coalesce(p.preparation_time_minutes, 15) * oi.quantity))::integer
          end
          from public.order_items oi
          left join public.products p on p.id = oi.product_id
          where oi.order_id = old.order_id
        ),
        updated_at = pg_catalog.now()
    where o.id = old.order_id;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists order_items_refresh_estimated_ready_minutes on public.order_items;
create trigger order_items_refresh_estimated_ready_minutes
after insert or update or delete on public.order_items
for each row execute function public.refresh_order_estimated_ready_minutes();

revoke all on function public.refresh_order_estimated_ready_minutes() from public, anon, authenticated;

-- Recalculate existing orders once, preserving null for orders without items.
update public.orders o
set estimated_ready_minutes = (
  select case when count(*) = 0 then null
    else greatest(1, sum(coalesce(p.preparation_time_minutes, 15) * oi.quantity))::integer
  end
  from public.order_items oi
  left join public.products p on p.id = oi.product_id
  where oi.order_id = o.id
)
where exists (select 1 from public.order_items oi where oi.order_id = o.id);

commit;
