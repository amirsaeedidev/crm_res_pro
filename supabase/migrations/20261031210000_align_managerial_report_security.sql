-- Align sales recognition with completed_at and remove SECURITY DEFINER
-- from read-only managerial reports. Restrict customer counts to customers.
create or replace function public.get_sales_report(start_date text, end_date text)
returns json
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  result json;
  v_start timestamptz := start_date::timestamptz;
  v_end timestamptz := end_date::timestamptz;
  v_previous_start timestamptz;
  v_previous_sales numeric := 0;
  v_total_sales numeric := 0;
begin
  if auth.uid() is null or not coalesce(public.is_admin(), false) then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if v_start is null or v_end is null or v_end < v_start then
    raise exception 'Invalid report date range' using errcode = '22023';
  end if;
  v_previous_start := v_start - (v_end - v_start);

  select coalesce(sum(o.total_amount),0) into v_total_sales
  from public.orders o
  where o.status='completed'
    and coalesce(o.completed_at,o.created_at)>=v_start
    and coalesce(o.completed_at,o.created_at)<=v_end;

  select coalesce(sum(o.total_amount),0) into v_previous_sales
  from public.orders o
  where o.status='completed'
    and coalesce(o.completed_at,o.created_at)>=v_previous_start
    and coalesce(o.completed_at,o.created_at)<v_start;

  select json_build_object(
    'id','sales_report',
    'type','sales',
    'summary',json_build_object(
      'total_sales',v_total_sales,
      'total_orders',(select count(*) from public.orders o where o.status='completed' and coalesce(o.completed_at,o.created_at)>=v_start and coalesce(o.completed_at,o.created_at)<=v_end),
      'delivery_count',(select count(*) from public.orders o where o.status='completed' and o.order_type='delivery' and coalesce(o.completed_at,o.created_at)>=v_start and coalesce(o.completed_at,o.created_at)<=v_end),
      'pickup_count',(select count(*) from public.orders o where o.status='completed' and o.order_type='pickup' and coalesce(o.completed_at,o.created_at)>=v_start and coalesce(o.completed_at,o.created_at)<=v_end),
      'dine_in_count',(select count(*) from public.orders o where o.status='completed' and o.order_type='dine_in' and coalesce(o.completed_at,o.created_at)>=v_start and coalesce(o.completed_at,o.created_at)<=v_end),
      'previous_period_sales',v_previous_sales,
      'growth_percentage',case when v_previous_sales=0 then case when v_total_sales=0 then 0 else 100 end else round(((v_total_sales-v_previous_sales)/v_previous_sales)*100,2) end
    ),
    'chart_data',(select coalesce(json_agg(json_build_object('date',d.sale_date,'amount',d.amount) order by d.sale_date),'[]'::json)
      from (
        select to_char((coalesce(o.completed_at,o.created_at) at time zone 'Asia/Baku')::date,'YYYY-MM-DD') sale_date,
               sum(o.total_amount) amount
        from public.orders o
        where o.status='completed'
          and coalesce(o.completed_at,o.created_at)>=v_start
          and coalesce(o.completed_at,o.created_at)<=v_end
        group by (coalesce(o.completed_at,o.created_at) at time zone 'Asia/Baku')::date
      ) d),
    'start_date',start_date,'end_date',end_date,'created_at',pg_catalog.now()
  ) into result;
  return result;
end;
$function$;

create or replace function public.get_top_products(limit_count integer default 10)
returns json
language plpgsql
security invoker
set search_path = ''
as $function$
declare result json;
begin
  if auth.uid() is null or not coalesce(public.is_admin(), false) then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if limit_count is null or limit_count < 1 or limit_count > 50 then
    raise exception 'Invalid product report limit' using errcode = '22023';
  end if;

  select pg_catalog.json_build_object(
    'id', 'top_products',
    'type', 'top_products',
    'summary', pg_catalog.json_build_object('limit', limit_count, 'period', 'all_time'),
    'chart_data', (
      select coalesce(
        pg_catalog.json_agg(
          pg_catalog.json_build_object(
            'product_name', d.name,
            'quantity', d.quantity,
            'total_amount', d.total_amount
          ) order by d.quantity desc, d.total_amount desc
        ), '[]'::json
      )
      from (
        select p.name, coalesce(s.quantity, 0) as quantity,
               coalesce(s.total_amount, 0) as total_amount
        from public.products p
        left join (
          select oi.product_id, sum(oi.quantity) as quantity,
                 sum(oi.total_price) as total_amount
          from public.order_items oi
          join public.orders o on o.id = oi.order_id
          where o.status = 'completed'
          group by oi.product_id
        ) s on s.product_id = p.id
        order by coalesce(s.quantity, 0) desc, coalesce(s.total_amount, 0) desc
        limit limit_count
      ) d
    ),
    'start_date', pg_catalog.now(),
    'end_date', pg_catalog.now(),
    'created_at', pg_catalog.now()
  ) into result;
  return result;
end;
$function$;

create or replace function public.get_customer_distribution()
returns json
language plpgsql
security invoker
set search_path = ''
as $function$
declare result json;
begin
  if auth.uid() is null or not coalesce(public.is_admin(), false) then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;

  select json_build_object(
    'id', 'customer_distribution',
    'type', 'customer_distribution',
    'summary', json_build_object(
      'total', (select count(*) from public.profiles p where p.role = 'customer')
    ),
    'chart_data', json_build_array(
      json_build_object('label','Delivery Customers','value',(
        select count(distinct o.user_id) from public.orders o
        join public.profiles p on p.id=o.user_id
        where p.role='customer' and o.status='completed' and o.order_type='delivery'
      )),
      json_build_object('label','Pickup Customers','value',(
        select count(distinct o.user_id) from public.orders o
        join public.profiles p on p.id=o.user_id
        where p.role='customer' and o.status='completed' and o.order_type='pickup'
      )),
      json_build_object('label','Dine-in Customers','value',(
        select count(distinct o.user_id) from public.orders o
        join public.profiles p on p.id=o.user_id
        where p.role='customer' and o.status='completed' and o.order_type='dine_in'
      ))
    ),
    'start_date',pg_catalog.now(),'end_date',pg_catalog.now(),'created_at',pg_catalog.now()
  ) into result;
  return result;
end;
$function$;
