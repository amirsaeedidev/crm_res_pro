-- Table utilization and peak dine-in hours analytics.
create or replace function public.get_table_usage_report(
  start_date timestamptz,
  end_date timestamptz
)
returns jsonb
language plpgsql
security invoker
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

  with dine_in as (
    select o.id, o.table_id, o.table_number, o.created_at,
      coalesce(o.completed_at, least(pg_catalog.now(), end_date)) as finished_at
    from public.orders o
    where o.order_type = 'dine_in' and o.table_id is not null
      and o.status <> 'cancelled' and o.created_at < end_date
      and coalesce(o.completed_at, pg_catalog.now()) > start_date
  ),
  clipped as (
    select d.*, greatest(d.created_at, start_date) as occupied_from,
      least(d.finished_at, end_date) as occupied_to
    from dine_in d
  ),
  table_rows as (
    select t.id as table_id, t.table_number, t.capacity,
      count(c.id) filter (where c.created_at >= start_date and c.created_at < end_date) as order_count,
      coalesce(sum(greatest(0, extract(epoch from (c.occupied_to - c.occupied_from)) / 60)), 0)::numeric as occupied_minutes,
      coalesce(avg(extract(epoch from (c.occupied_to - c.occupied_from)) / 60)
        filter (where c.created_at >= start_date and c.created_at < end_date), 0)::numeric as average_minutes
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
    select extract(hour from (o.created_at at time zone 'Asia/Baku'))::integer as hour,
      count(*)::bigint as order_count
    from public.orders o
    where o.order_type = 'dine_in' and o.table_id is not null
      and o.status <> 'cancelled' and o.created_at >= start_date and o.created_at < end_date
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

  with dine_in as (
    select o.id, o.created_at,
      coalesce(o.completed_at, least(pg_catalog.now(), end_date)) as finished_at
    from public.orders o
    where o.order_type = 'dine_in' and o.table_id is not null
      and o.status <> 'cancelled' and o.created_at < end_date
      and coalesce(o.completed_at, pg_catalog.now()) > start_date
  )
  select jsonb_build_object(
    'total_orders', count(*) filter (where created_at >= start_date and created_at < end_date),
    'occupied_minutes', round(coalesce(sum(greatest(0, extract(epoch from
      (least(finished_at, end_date) - greatest(created_at, start_date))) / 60)), 0)::numeric, 1),
    'average_minutes', round(coalesce(avg(extract(epoch from (finished_at - created_at))
      / 60) filter (where created_at >= start_date and created_at < end_date), 0)::numeric, 1),
    'peak_hour', v_peak_hour, 'peak_hour_orders', v_peak_count
  ) into v_summary from dine_in;

  return jsonb_build_object(
    'id', 'table_usage', 'type', 'table_usage', 'summary', v_summary,
    'chart_data', jsonb_build_object('tables', v_tables, 'hours', v_hours),
    'start_date', start_date, 'end_date', end_date, 'created_at', pg_catalog.now()
  );
end;
$function$;

revoke all on function public.get_table_usage_report(timestamptz, timestamptz) from public, anon;
grant execute on function public.get_table_usage_report(timestamptz, timestamptz) to authenticated;
