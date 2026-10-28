-- Order health reports: cancellations, delays and repeat customers.
-- Apply through Supabase migration tooling or SQL Editor.
begin;

create or replace function public.get_order_health_report(
  start_date timestamptz,
  end_date timestamptz
)
returns json
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_cancelled bigint := 0;
  v_cancelled_amount numeric := 0;
  v_delayed bigint := 0;
  v_repeat_customers bigint := 0;
  v_rows json := '[]'::json;
begin
  if not (select public.is_admin()) then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if start_date is null or end_date is null or end_date < start_date then
    raise exception 'Invalid report date range' using errcode = '22023';
  end if;

  select count(*), coalesce(sum(o.total_amount), 0)
    into v_cancelled, v_cancelled_amount
  from public.orders o
  where o.created_at >= start_date and o.created_at <= end_date
    and lower(coalesce(o.status, '')) in ('cancelled', 'canceled', 'لغو شده', 'لغو‌شده');

  select count(*) into v_delayed
  from public.orders o
  where o.created_at >= start_date and o.created_at <= end_date
    and lower(coalesce(o.status, '')) not in ('cancelled', 'canceled', 'لغو شده', 'لغو‌شده')
    and (
      (o.status = 'completed'
        and o.completed_at is not null
        and o.estimated_ready_minutes is not null
        and o.completed_at > o.created_at + make_interval(mins => greatest(o.estimated_ready_minutes, 1)))
      or
      (o.status not in ('completed', 'cancelled', 'canceled')
        and now() > o.created_at + make_interval(mins => greatest(coalesce(o.estimated_ready_minutes, 15), 15)))
    );

  select count(*) into v_repeat_customers
  from (
    select coalesce(nullif(trim(o.customer_phone), ''), o.user_id::text) as customer_key
    from public.orders o
    where o.created_at >= start_date and o.created_at <= end_date
      and coalesce(nullif(trim(o.customer_phone), ''), o.user_id::text) is not null
    group by coalesce(nullif(trim(o.customer_phone), ''), o.user_id::text)
    having count(*) >= 3
  ) repeaters;

  select coalesce(json_agg(row_data order by sort_group, sort_time desc), '[]'::json)
    into v_rows
  from (
    select 1 as sort_group, o.created_at as sort_time,
      json_build_object(
        'category', 'cancelled',
        'order_id', o.id,
        'daily_queue_number', o.daily_queue_number,
        'customer_name', coalesce(o.customer_name, 'مشتری نامشخص'),
        'customer_phone', coalesce(o.customer_phone, ''),
        'status', o.status,
        'amount', coalesce(o.total_amount, 0),
        'reason', coalesce(o.cancellation_reason, ''),
        'created_at', o.created_at,
        'delay_minutes', 0,
        'order_count', 0
      ) as row_data
    from public.orders o
    where o.created_at >= start_date and o.created_at <= end_date
      and lower(coalesce(o.status, '')) in ('cancelled', 'canceled', 'لغو شده', 'لغو‌شده')
    union all
    select 2, o.created_at,
      json_build_object(
        'category', 'delayed',
        'order_id', o.id,
        'daily_queue_number', o.daily_queue_number,
        'customer_name', coalesce(o.customer_name, 'مشتری نامشخص'),
        'customer_phone', coalesce(o.customer_phone, ''),
        'status', o.status,
        'amount', coalesce(o.total_amount, 0),
        'reason', '',
        'created_at', o.created_at,
        'delay_minutes', greatest(
          0,
          floor(extract(epoch from (
            coalesce(o.completed_at, now()) -
            (o.created_at + make_interval(mins => greatest(coalesce(o.estimated_ready_minutes, 15), 15)))
          )) / 60)::int
        ),
        'order_count', 0
      )
    from public.orders o
    where o.created_at >= start_date and o.created_at <= end_date
      and lower(coalesce(o.status, '')) not in ('cancelled', 'canceled', 'لغو شده', 'لغو‌شده')
      and (
        (o.status = 'completed' and o.completed_at is not null
          and o.estimated_ready_minutes is not null
          and o.completed_at > o.created_at + make_interval(mins => greatest(o.estimated_ready_minutes, 1)))
        or
        (o.status not in ('completed', 'cancelled', 'canceled')
          and now() > o.created_at + make_interval(mins => greatest(coalesce(o.estimated_ready_minutes, 15), 15)))
      )
    union all
    select 3, max(o.created_at),
      json_build_object(
        'category', 'repeat_customer',
        'order_id', '',
        'daily_queue_number', null,
        'customer_name', coalesce(max(o.customer_name), 'مشتری نامشخص'),
        'customer_phone', coalesce(max(nullif(trim(o.customer_phone), '')), o.user_id::text, ''),
        'status', 'repeat_customer',
        'amount', coalesce(sum(o.total_amount), 0),
        'reason', '',
        'created_at', max(o.created_at),
        'delay_minutes', 0,
        'order_count', count(*)
      )
    from public.orders o
    where o.created_at >= start_date and o.created_at <= end_date
      and coalesce(nullif(trim(o.customer_phone), ''), o.user_id::text) is not null
    group by coalesce(nullif(trim(o.customer_phone), ''), o.user_id::text)
    having count(*) >= 3
  ) report_rows;

  return json_build_object(
    'id', 'order_health_report',
    'type', 'order_health',
    'summary', json_build_object(
      'cancelled_count', v_cancelled,
      'cancelled_amount', v_cancelled_amount,
      'delayed_count', v_delayed,
      'repeat_customer_count', v_repeat_customers,
      'repeat_customer_threshold', 3,
      'delay_rule', 'Active orders are delayed after at least 15 minutes or the estimated preparation time; completed orders are delayed when completion exceeded the estimate.'
    ),
    'chart_data', v_rows,
    'start_date', start_date,
    'end_date', end_date,
    'created_at', now()
  );
end;
$$;

revoke all on function public.get_order_health_report(timestamptz, timestamptz) from public, anon;
grant execute on function public.get_order_health_report(timestamptz, timestamptz) to authenticated;
commit;
