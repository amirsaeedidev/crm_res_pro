-- Convert an existing reservation into exactly one dine-in order.
-- The RPC runs as invoker so existing admin RLS policies remain authoritative.
begin;

create or replace function public.guard_dine_in_table_availability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_claim_table boolean := false;
  v_available boolean;
  v_now_local timestamp without time zone := pg_catalog.now() at time zone 'Asia/Baku';
  v_conversion_reservation_id uuid :=
    nullif(pg_catalog.current_setting('app.reservation_conversion_id', true), '')::uuid;
begin
  if new.order_type <> 'dine_in' or new.status in ('completed','cancelled') then
    return new;
  end if;
  if new.table_id is null or new.table_number is null then
    raise exception 'A valid table must be selected for dine-in orders' using errcode = '22023';
  end if;
  if tg_op = 'INSERT' then
    v_claim_table := true;
  elsif old.table_id is distinct from new.table_id then
    v_claim_table := true;
  elsif old.status in ('completed','cancelled') then
    v_claim_table := true;
  end if;
  if v_claim_table then
    select
      rt.is_active
      and rt.table_number = new.table_number
      and not rt.is_occupied
      and not exists (
        select 1 from public.orders o
        where o.table_id = rt.id and o.id is distinct from new.id
          and o.order_type = 'dine_in'
          and o.status in ('pending','confirmed','preparing','ready')
      )
      and not exists (
        select 1 from public.reservations r
        where r.table_id = rt.id
          and r.id is distinct from v_conversion_reservation_id
          and r.status in ('pending','confirmed','delayed','arrived')
          and r.reservation_date is not null and r.reservation_time is not null
          and (r.reservation_date + r.reservation_time) <= v_now_local
          and (r.reservation_date + r.reservation_time
            + pg_catalog.make_interval(mins => r.duration_minutes)) > v_now_local
      )
    into v_available
    from public.restaurant_tables rt
    where rt.id = new.table_id
    for update;
    if not coalesce(v_available, false) then
      raise exception 'The selected table is unavailable. Please choose another table.'
        using errcode = '22023';
    end if;
  end if;
  return new;
end;
$function$;

create or replace function public.convert_reservation_to_order(p_reservation_id uuid)
returns uuid
language plpgsql
security invoker
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
    raise exception 'فقط مدیر فعال می‌تواند رزرو را به سفارش تبدیل کند.' using errcode = '42501';
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
    raise exception 'این رزرو به دلیل وضعیت فعلی قابل تبدیل به سفارش نیست.' using errcode = '22023';
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
    discount_amount, delivery_fee, table_id, table_number, note
  ) values (
    v_reservation.user_id, 'dine_in', 'pending', 0, 0,
    0, 0, v_reservation.table_id, v_table_number, v_reservation.note
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

revoke all on function public.convert_reservation_to_order(uuid) from public, anon;
grant execute on function public.convert_reservation_to_order(uuid) to authenticated;

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

commit;
