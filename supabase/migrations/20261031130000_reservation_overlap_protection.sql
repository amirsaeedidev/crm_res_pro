-- Prevent overlapping active reservations for the same restaurant table.
-- The table-row lock serializes concurrent inserts/updates for a table.
-- Reservation duration defaults to 90 minutes and can be changed per row.

begin;

alter table public.reservations
  add column if not exists duration_minutes integer not null default 90;

alter table public.reservations
  drop constraint if exists reservations_duration_minutes_check;

alter table public.reservations
  add constraint reservations_duration_minutes_check
  check (duration_minutes between 15 and 480);

create schema if not exists extensions;
create extension if not exists btree_gist with schema extensions;
set local search_path = public, extensions;

-- Remove legacy uniqueness rules that blocked every second active reservation
-- on a table, even when it was scheduled for a different time.
drop index if exists public.idx_reservation_active_table;
drop index if exists public.reservations_active_slot_unique_idx;

alter table public.reservations
  drop constraint if exists reservations_no_overlapping_active_table_time;

alter table public.reservations
  add constraint reservations_no_overlapping_active_table_time
  exclude using gist (
    table_id with =,
    tsrange(
      reservation_date + reservation_time,
      reservation_date + reservation_time + make_interval(mins => duration_minutes),
      '[)'
    ) with &&
  )
  where (status in ('pending', 'confirmed')
    and reservation_date is not null
    and reservation_time is not null);

create or replace function public.enforce_reservation_time_overlap()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_start timestamp without time zone;
  v_end timestamp without time zone;
  v_conflict boolean;
begin
  if new.status not in ('pending', 'confirmed')
     or new.table_id is null
     or new.reservation_date is null
     or new.reservation_time is null then
    return new;
  end if;

  perform 1
    from public.restaurant_tables
   where id = new.table_id
   for update;

  if not found then
    raise exception using errcode = '23503',
      message = 'میز انتخاب‌شده وجود ندارد.';
  end if;

  v_start := new.reservation_date + new.reservation_time;
  v_end := v_start + make_interval(mins => new.duration_minutes);

  select exists (
    select 1
      from public.reservations r
     where r.table_id = new.table_id
       and r.id <> new.id
       and r.status in ('pending', 'confirmed')
       and r.reservation_date is not null
       and r.reservation_time is not null
       and (r.reservation_date + r.reservation_time) < v_end
       and (r.reservation_date + r.reservation_time
            + make_interval(mins => r.duration_minutes)) > v_start
  ) into v_conflict;

  if v_conflict then
    raise exception using errcode = '23P01',
      message = 'این میز در بخشی از بازه زمانی انتخاب‌شده رزرو فعال دارد. زمان دیگری انتخاب کنید.';
  end if;

  return new;
end;
$function$;

drop trigger if exists reservations_prevent_time_overlap on public.reservations;
create trigger reservations_prevent_time_overlap
before insert or update of table_id, reservation_date, reservation_time, duration_minutes, status
on public.reservations
for each row execute function public.enforce_reservation_time_overlap();

revoke all on function public.enforce_reservation_time_overlap() from public, anon, authenticated;

-- is_occupied represents an active dine-in order only. Reservation state is
-- calculated separately by the CRM for the selected date.
create or replace function public.refresh_restaurant_table_occupancy(p_table_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if p_table_id is null then
    return;
  end if;

  update public.restaurant_tables as rt
     set is_occupied = exists (
       select 1
         from public.orders as o
        where o.table_id = rt.id
          and o.order_type = 'dine_in'
          and o.status in ('pending','confirmed','preparing','ready')
     ),
         updated_at = now()
   where rt.id = p_table_id;
end;
$function$;

update public.restaurant_tables rt
   set is_occupied = exists (
     select 1
       from public.orders o
      where o.table_id = rt.id
        and o.order_type = 'dine_in'
        and o.status in ('pending','confirmed','preparing','ready')
   ),
       updated_at = now();

commit;
