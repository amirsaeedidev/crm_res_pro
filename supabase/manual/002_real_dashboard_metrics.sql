-- Replace hard-coded dashboard growth rates with measured database values.
-- Review this script, then run it in Supabase SQL Editor before releasing the app.
-- This is not executed automatically by the Flutter client.

begin;

create or replace function public.get_dashboard_stats()
returns json
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_now timestamptz := pg_catalog.now();
  v_current_month_start timestamptz := pg_catalog.date_trunc('month', pg_catalog.now());
  v_previous_month_start timestamptz := pg_catalog.date_trunc('month', pg_catalog.now()) - interval '1 month';
  v_current_sales numeric := 0;
  v_previous_sales numeric := 0;
  v_current_orders bigint := 0;
  v_previous_orders bigint := 0;
  v_current_customers bigint := 0;
  v_previous_customers bigint := 0;
  v_total_sales numeric := 0;
  v_total_orders bigint := 0;
  v_total_customers bigint := 0;
  v_total_products bigint := 0;
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;

  select coalesce(sum(o.total_amount), 0)
    into v_total_sales
    from public.orders o
   where o.status = 'completed';

  select count(*) into v_total_orders from public.orders;
  select count(*) into v_total_customers from public.profiles p where p.role = 'customer';
  select count(*) into v_total_products from public.products p where p.is_active = true;

  select coalesce(sum(o.total_amount), 0)
    into v_current_sales
    from public.orders o
   where o.status = 'completed'
     and o.created_at >= v_current_month_start
     and o.created_at < v_now;

  select coalesce(sum(o.total_amount), 0)
    into v_previous_sales
    from public.orders o
   where o.status = 'completed'
     and o.created_at >= v_previous_month_start
     and o.created_at < v_current_month_start;

  select count(*) into v_current_orders
    from public.orders o
   where o.created_at >= v_current_month_start and o.created_at < v_now;

  select count(*) into v_previous_orders
    from public.orders o
   where o.created_at >= v_previous_month_start and o.created_at < v_current_month_start;

  select count(*) into v_current_customers
    from public.profiles p
   where p.role = 'customer'
     and p.created_at >= v_current_month_start and p.created_at < v_now;

  select count(*) into v_previous_customers
    from public.profiles p
   where p.role = 'customer'
     and p.created_at >= v_previous_month_start and p.created_at < v_current_month_start;

  return pg_catalog.json_build_object(
    'total_sales', v_total_sales,
    'total_orders', v_total_orders,
    'total_customers', v_total_customers,
    'total_products', v_total_products,
    'sales_growth_percentage', case
      when v_previous_sales = 0 then case when v_current_sales = 0 then 0 else 100 end
      else pg_catalog.round(((v_current_sales - v_previous_sales) / v_previous_sales) * 100, 2)
    end,
    'orders_growth_percentage', case
      when v_previous_orders = 0 then case when v_current_orders = 0 then 0 else 100 end
      else pg_catalog.round(((v_current_orders::numeric - v_previous_orders::numeric) / v_previous_orders) * 100, 2)
    end,
    'customers_growth_percentage', case
      when v_previous_customers = 0 then case when v_current_customers = 0 then 0 else 100 end
      else pg_catalog.round(((v_current_customers::numeric - v_previous_customers::numeric) / v_previous_customers) * 100, 2)
    end,
    'period', 'monthly',
    'updated_at', v_now
  );
end;
$function$;

-- Top products should be calculated only from completed orders, not cancelled or pending carts.
create or replace function public.get_top_products(limit_count integer default 10)
returns json
language plpgsql
security definer
set search_path to ''
as $function$
declare
  result json;
begin
  if not public.is_admin() then
    raise exception 'Administrator access required';
  end if;

  select pg_catalog.json_build_object(
    'id', pg_catalog.gen_random_uuid(),
    'type', 'top_products',
    'summary', pg_catalog.json_build_object('limit', greatest(limit_count, 0)),
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
        select p.name,
               coalesce(sum(case when o.status = 'completed' then oi.quantity else 0 end), 0) as quantity,
               coalesce(sum(case when o.status = 'completed' then oi.total_price else 0 end), 0) as total_amount
          from public.products p
          left join public.order_items oi on oi.product_id = p.id
          left join public.orders o on o.id = oi.order_id
         group by p.id, p.name
         order by quantity desc, total_amount desc
         limit greatest(limit_count, 0)
      ) d
    ),
    'start_date', pg_catalog.now(),
    'end_date', pg_catalog.now(),
    'created_at', pg_catalog.now()
  ) into result;

  return result;
end;
$function$;

commit;
