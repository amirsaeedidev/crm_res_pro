-- Track attendance and preserve a status audit trail for reservations.
begin;

alter table public.reservations
  add column if not exists arrived_at timestamptz,
  add column if not exists delayed_at timestamptz,
  add column if not exists delay_minutes integer,
  add column if not exists delay_note text,
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancellation_reason text,
  add column if not exists no_show_at timestamptz;

alter table public.reservations
  drop constraint if exists reservations_status_check,
  drop constraint if exists reservations_delay_minutes_check;

alter table public.reservations
  add constraint reservations_status_check
    check (status in ('pending','confirmed','delayed','arrived','completed','cancelled','no_show')),
  add constraint reservations_delay_minutes_check
    check (delay_minutes is null or delay_minutes between 1 and 480);

alter table public.reservations drop constraint if exists reservations_no_overlapping_active_table_time;
alter table public.reservations
  add constraint reservations_no_overlapping_active_table_time
  exclude using gist (
    table_id with =,
    tsrange(reservation_date + reservation_time,
      reservation_date + reservation_time + make_interval(mins => duration_minutes), '[)') with &&
  )
  where (status in ('pending','confirmed','delayed','arrived')
    and reservation_date is not null and reservation_time is not null);

create or replace function public.enforce_reservation_time_overlap()
returns trigger language plpgsql security definer set search_path = ''
as $function$
declare
  v_start timestamp without time zone;
  v_end timestamp without time zone;
  v_conflict boolean;
begin
  if new.status not in ('pending','confirmed','delayed','arrived')
     or new.table_id is null or new.reservation_date is null or new.reservation_time is null then
    return new;
  end if;
  perform 1 from public.restaurant_tables where id = new.table_id for update;
  if not found then
    raise exception using errcode = '23503', message = 'میز انتخاب‌شده وجود ندارد.';
  end if;
  v_start := new.reservation_date + new.reservation_time;
  v_end := v_start + make_interval(mins => new.duration_minutes);
  select exists (
    select 1 from public.reservations r
    where r.table_id = new.table_id and r.id <> new.id
      and r.status in ('pending','confirmed','delayed','arrived')
      and r.reservation_date is not null and r.reservation_time is not null
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

create schema if not exists private;

create or replace function private.stamp_reservation_attendance_fields()
returns trigger language plpgsql set search_path = ''
as $function$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    if new.status = 'arrived' then
      new.arrived_at := coalesce(new.arrived_at, now());
    elsif new.status = 'delayed' then
      new.delayed_at := coalesce(new.delayed_at, now());
      if new.delay_minutes is null then
        raise exception using errcode = '23514', message = 'برای ثبت تأخیر، تعداد دقیقه تأخیر الزامی است.';
      end if;
    elsif new.status = 'cancelled' then
      new.cancelled_at := coalesce(new.cancelled_at, now());
    elsif new.status = 'no_show' then
      new.no_show_at := coalesce(new.no_show_at, now());
    end if;
    if tg_op = 'UPDATE' and old.status = 'cancelled' and new.status <> 'cancelled' then
      new.cancelled_at := null;
      new.cancellation_reason := null;
    end if;
    if tg_op = 'UPDATE' and old.status = 'no_show' and new.status <> 'no_show' then
      new.no_show_at := null;
    end if;
  elsif new.status = 'delayed' and new.delay_minutes is null then
    raise exception using errcode = '23514', message = 'برای ثبت تأخیر، تعداد دقیقه تأخیر الزامی است.';
  end if;
  return new;
end;
$function$;

drop trigger if exists reservations_stamp_attendance_fields on public.reservations;
create trigger reservations_stamp_attendance_fields
before insert or update of status, delay_minutes on public.reservations
for each row execute function private.stamp_reservation_attendance_fields();

create table if not exists public.reservation_status_history (
  id uuid primary key default gen_random_uuid(),
  reservation_id uuid not null references public.reservations(id) on delete cascade,
  previous_status text,
  new_status text not null check (new_status in ('pending','confirmed','delayed','arrived','completed','cancelled','no_show')),
  changed_at timestamptz not null default now(),
  changed_by uuid references auth.users(id) on delete set null,
  delay_minutes integer,
  note text
);
create index if not exists reservation_status_history_reservation_time_idx
  on public.reservation_status_history (reservation_id, changed_at desc);

alter table public.reservation_status_history enable row level security;
revoke all on public.reservation_status_history from anon, authenticated;
grant select on public.reservation_status_history to authenticated;
drop policy if exists reservation_status_history_admin_read on public.reservation_status_history;
create policy reservation_status_history_admin_read on public.reservation_status_history
  for select to authenticated using ((select public.is_admin()));

create or replace function private.capture_reservation_status_history()
returns trigger language plpgsql security definer set search_path = ''
as $function$
begin
  if tg_op = 'INSERT'
     or new.status is distinct from old.status
     or new.delay_minutes is distinct from old.delay_minutes
     or new.delay_note is distinct from old.delay_note
     or new.cancellation_reason is distinct from old.cancellation_reason then
    insert into public.reservation_status_history
      (reservation_id, previous_status, new_status, changed_by, delay_minutes, note)
    values (
      new.id,
      case when tg_op = 'INSERT' then null else old.status end,
      new.status,
      auth.uid(),
      new.delay_minutes,
      case when new.status = 'delayed' then new.delay_note
           when new.status = 'cancelled' then new.cancellation_reason else null end
    );
  end if;
  return new;
end;
$function$;

drop trigger if exists reservations_capture_status_history on public.reservations;
create trigger reservations_capture_status_history
after insert or update of status, delay_minutes, delay_note, cancellation_reason on public.reservations
for each row execute function private.capture_reservation_status_history();

revoke all on function private.stamp_reservation_attendance_fields() from public, anon, authenticated;
revoke all on function private.capture_reservation_status_history() from public, anon, authenticated;
revoke all on function public.enforce_reservation_time_overlap() from public, anon, authenticated;

create or replace view public.reservations_view with (security_invoker = true) as
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
  r.table_id,
  r.duration_minutes,
  r.arrived_at,
  r.delayed_at,
  r.delay_minutes,
  r.delay_note,
  r.cancelled_at,
  r.cancellation_reason,
  r.no_show_at
from public.reservations r
left join public.profiles p on p.id = r.user_id
left join public.restaurant_tables t on t.id = r.table_id;

commit;
