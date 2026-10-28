-- MANUAL SCHEMA PREREQUISITE for the CRM reservation management screen.
-- Review before running in the Supabase SQL Editor. This is intentionally NOT
-- auto-applied by the app because it changes the shared production schema.

begin;

alter table public.reservations
  add column if not exists reservation_date date,
  add column if not exists reservation_time time without time zone,
  add column if not exists note text;

-- Backfill existing reservations so the view remains useful after this change.
update public.reservations
set reservation_date = coalesce(reservation_date, created_at::date),
    reservation_time = coalesce(reservation_time, created_at::time)
where reservation_date is null or reservation_time is null;

create index if not exists reservations_schedule_idx
  on public.reservations (reservation_date, reservation_time);

create index if not exists reservations_table_status_idx
  on public.reservations (table_id, status);

-- Stop two concurrent admin sessions from booking the same table/slot.
-- Refuse to install the constraint if existing data already has collisions;
-- the script never silently deletes or changes a reservation.
do $block$
begin
  if exists (
    select 1
      from public.reservations
     where status in ('pending', 'confirmed')
     group by table_id, reservation_date, reservation_time
    having count(*) > 1
  ) then
    raise exception 'Duplicate active table/date/time reservations exist. Resolve those records before adding reservations_active_slot_unique_idx.';
  end if;
end;
$block$;

create unique index if not exists reservations_active_slot_unique_idx
  on public.reservations (table_id, reservation_date, reservation_time)
  where status in ('pending', 'confirmed');

-- Keep the existing first 11 view columns and their types/positions stable;
-- append user_id/table_id for admin editing. `security_invoker` keeps the
-- view subject to the requesting role's underlying table RLS policies.
create or replace view public.reservations_view
with (security_invoker = true)
as
select
  r.id,
  (coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, ''))::text as customer_name,
  coalesce(p.phone, '')::text as customer_phone,
  coalesce(r.reservation_date::text, r.created_at::date::text) as date,
  coalesce(to_char(r.reservation_time, 'HH24:MI'), to_char(r.created_at, 'HH24:MI'))::text as time,
  r.guest_count as party_size,
  t.table_number::text as table_number,
  coalesce(r.note, '')::text as note,
  r.status,
  r.created_at,
  r.updated_at,
  r.user_id,
  r.table_id
from public.reservations r
left join public.profiles p on p.id = r.user_id
left join public.restaurant_tables t on t.id = r.table_id;

commit;
