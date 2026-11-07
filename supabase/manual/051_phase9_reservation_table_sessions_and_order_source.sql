begin;

alter table public.orders
  add column if not exists order_source text not null default 'customer_app',
  add column if not exists table_started_at timestamptz,
  add column if not exists table_ended_at timestamptz;

alter table public.orders
  drop constraint if exists orders_order_source_check;
alter table public.orders
  add constraint orders_order_source_check
  check (order_source in ('customer_app', 'crm_walk_in', 'reservation'));

update public.orders o
set order_source = 'reservation'
where exists (
  select 1 from public.reservations r
  where r.order_id = o.id
);

create index if not exists orders_table_source_created_idx
  on public.orders (table_id, order_source, created_at desc)
  where table_id is not null;

create or replace function public.track_dine_in_table_session()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.order_type <> 'dine_in' or new.table_id is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.table_started_at := coalesce(new.table_started_at, pg_catalog.now());
    if new.status in ('completed', 'cancelled') then
      new.table_ended_at := coalesce(new.table_ended_at, pg_catalog.now());
    end if;
  elsif new.status is distinct from old.status then
    if new.status in ('pending', 'confirmed', 'preparing', 'ready', 'out_for_delivery')
       and new.table_started_at is null then
      new.table_started_at := pg_catalog.now();
    end if;
    if new.status in ('completed', 'cancelled') then
      new.table_ended_at := coalesce(new.table_ended_at, pg_catalog.now());
    elsif new.status in ('pending', 'confirmed', 'preparing', 'ready', 'out_for_delivery') then
      new.table_ended_at := null;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists orders_track_dine_in_table_session on public.orders;
create trigger orders_track_dine_in_table_session
before insert or update of status, table_id, order_type
on public.orders
for each row execute function public.track_dine_in_table_session();

create or replace function public.convert_reservation_to_order(p_reservation_id uuid)
returns uuid
language plpgsql
set search_path = ''
as $function$
declare
  v_reservation public.reservations%rowtype;
  v_table_number integer;
  v_capacity integer;
  v_is_active boolean;
  v_order_id uuid;
begin
  if auth.uid() is null or not coalesce(public.is_admin(), false) then
    raise exception 'فقط مدیر فعال می‌تواند رزرو را به سفارش تبدیل کند.'
      using errcode = '42501';
  end if;

  select r.* into v_reservation
  from public.reservations r
  where r.id = p_reservation_id
  for update;

  if not found then
    raise exception 'رزرو موردنظر پیدا نشد.' using errcode = 'P0002';
  end if;

  if v_reservation.order_id is not null then
    return v_reservation.order_id;
  end if;

  if v_reservation.status not in ('pending','confirmed','delayed','arrived') then
    raise exception 'این رزرو به دلیل وضعیت فعلی قابل تبدیل به سفارش نیست.'
      using errcode = '22023';
  end if;

  select t.table_number, t.capacity, t.is_active
  into v_table_number, v_capacity, v_is_active
  from public.restaurant_tables t
  where t.id = v_reservation.table_id
  for update;

  if not found or not v_is_active then
    raise exception 'میز رزرو غیرفعال است یا وجود ندارد.' using errcode = '22023';
  end if;

  if v_reservation.guest_count > v_capacity then
    raise exception 'تعداد مهمانان از ظرفیت میز بیشتر است.' using errcode = '22023';
  end if;

  if v_reservation.status <> 'arrived' then
    update public.reservations
    set status = 'arrived',
        arrived_at = coalesce(arrived_at, pg_catalog.now()),
        updated_at = pg_catalog.now()
    where id = p_reservation_id;
  end if;

  perform pg_catalog.set_config('app.reservation_conversion_id', p_reservation_id::text, true);

  insert into public.orders (
    user_id, order_type, status, total_amount, subtotal_amount,
    discount_amount, delivery_fee, table_id, table_number, note,
    order_source, table_started_at
  ) values (
    v_reservation.user_id, 'dine_in', 'pending', 0, 0,
    0, 0, v_reservation.table_id, v_table_number, v_reservation.note,
    'reservation', coalesce(v_reservation.arrived_at, pg_catalog.now())
  )
  returning id into v_order_id;

  update public.reservations
  set order_id = v_order_id, updated_at = pg_catalog.now()
  where id = p_reservation_id and order_id is null;

  if not found then
    raise exception 'اتصال سفارش به رزرو انجام نشد.' using errcode = '40001';
  end if;

  return v_order_id;
end;
$function$;

create or replace view public.orders_view
with (security_invoker = true)
as
select
  o.id,
  o.user_id,
  (coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')) as customer_name,
  coalesce(p.phone, '') as customer_phone,
  o.address_id,
  o.order_type,
  o.status,
  o.total_amount,
  o.estimated_ready_minutes,
  o.admin_note,
  o.completed_at,
  o.created_at,
  o.updated_at,
  o.assigned_staff_id,
  o.subtotal_amount,
  o.discount_amount,
  o.discount_code,
  o.table_number,
  o.daily_queue_number,
  o.address_line,
  o.table_id,
  o.cancellation_reason,
  o.note,
  case when o.status = 'completed' then coalesce(o.completed_at, o.created_at)
       else o.created_at end as order_date_filter,
  o.delivery_fee,
  o.order_source,
  o.table_started_at,
  o.table_ended_at
from public.orders o
left join public.profiles p on p.id = o.user_id;

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
  r.table_id,
  r.duration_minutes,
  r.arrived_at,
  r.delayed_at,
  r.delay_minutes,
  r.delay_note,
  r.cancelled_at,
  r.cancellation_reason,
  r.no_show_at,
  r.order_id
from public.reservations r
left join public.profiles p on p.id = r.user_id
left join public.restaurant_tables t on t.id = r.table_id;

create or replace function public.get_table_usage_report(
  start_date timestamptz,
  end_date timestamptz
)
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare
  v_summary jsonb;
  v_tables jsonb;
  v_hours jsonb;
  v_peak_hour integer;
  v_peak_count bigint;
begin
  if auth.uid() is null or not coalesce(public.is_admin(), false) then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if start_date is null or end_date is null or end_date <= start_date then
    raise exception 'Invalid report date range' using errcode = '22023';
  end if;

  with sessions as (
    select o.id, o.table_id, o.table_number,
      coalesce(o.table_started_at, o.created_at) as started_at,
      coalesce(o.table_ended_at, o.completed_at, least(pg_catalog.now(), end_date)) as ended_at
    from public.orders o
    where o.order_type = 'dine_in' and o.table_id is not null
      and o.status <> 'cancelled'
      and coalesce(o.table_started_at, o.created_at) < end_date
      and coalesce(o.table_ended_at, o.completed_at, pg_catalog.now()) > start_date
  ),
  clipped as (
    select s.*, greatest(s.started_at, start_date) as occupied_from,
      least(s.ended_at, end_date) as occupied_to
    from sessions s
  ),
  table_rows as (
    select t.id as table_id, t.table_number, t.capacity,
      count(c.id) filter (where c.started_at >= start_date and c.started_at < end_date) as order_count,
      coalesce(sum(greatest(0, extract(epoch from (c.occupied_to - c.occupied_from)) / 60)), 0)::numeric as occupied_minutes,
      coalesce(avg(extract(epoch from (c.ended_at - c.started_at)) / 60)
        filter (where c.started_at >= start_date and c.started_at < end_date), 0)::numeric as average_minutes
    from public.restaurant_tables t
    left join clipped c on c.table_id = t.id
    where t.is_active = true
    group by t.id, t.table_number, t.capacity
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'table_id', table_id, 'table_number', table_number, 'capacity', capacity,
    'order_count', order_count, 'occupied_minutes', round(occupied_minutes, 1),
    'average_minutes', round(average_minutes, 1)
  ) order by order_count desc, table_number), '[]'::jsonb)
  into v_tables from table_rows;

  with hours as (
    select extract(hour from (coalesce(o.table_started_at, o.created_at) at time zone 'Asia/Tehran'))::integer as hour,
      count(*)::bigint as order_count
    from public.orders o
    where o.order_type = 'dine_in' and o.table_id is not null
      and o.status <> 'cancelled'
      and coalesce(o.table_started_at, o.created_at) >= start_date
      and coalesce(o.table_started_at, o.created_at) < end_date
    group by 1
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'hour', h.hour, 'label', lpad(h.hour::text, 2, '0') || ':00',
      'order_count', coalesce(x.order_count, 0)
    ) order by h.hour), '[]'::jsonb),
    coalesce(max(x.order_count), 0),
    coalesce((array_agg(h.hour order by x.order_count desc nulls last, h.hour))[1], 0)
  into v_hours, v_peak_count, v_peak_hour
  from generate_series(0, 23) as h(hour)
  left join hours x on x.hour = h.hour;

  with sessions as (
    select o.id, coalesce(o.table_started_at, o.created_at) as started_at,
      coalesce(o.table_ended_at, o.completed_at, least(pg_catalog.now(), end_date)) as ended_at
    from public.orders o
    where o.order_type = 'dine_in' and o.table_id is not null
      and o.status <> 'cancelled'
      and coalesce(o.table_started_at, o.created_at) < end_date
      and coalesce(o.table_ended_at, o.completed_at, pg_catalog.now()) > start_date
  )
  select jsonb_build_object(
    'total_orders', count(*) filter (where started_at >= start_date and started_at < end_date),
    'occupied_minutes', round(coalesce(sum(greatest(0, extract(epoch from
      (least(ended_at, end_date) - greatest(started_at, start_date))) / 60)), 0)::numeric, 1),
    'average_minutes', round(coalesce(avg(extract(epoch from (ended_at - started_at)) / 60)
      filter (where started_at >= start_date and started_at < end_date), 0)::numeric, 1),
    'peak_hour', v_peak_hour, 'peak_hour_orders', v_peak_count
  ) into v_summary from sessions;

  return jsonb_build_object(
    'id', 'table_usage', 'type', 'table_usage', 'summary', v_summary,
    'chart_data', jsonb_build_object('tables', v_tables, 'hours', v_hours),
    'start_date', start_date, 'end_date', end_date, 'created_at', pg_catalog.now()
  );
end;
$function$;

revoke all on function public.get_table_usage_report(timestamptz,timestamptz) from public, anon;
grant execute on function public.get_table_usage_report(timestamptz,timestamptz) to authenticated;

commit;