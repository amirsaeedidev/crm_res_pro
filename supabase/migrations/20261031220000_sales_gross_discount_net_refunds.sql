-- Sales breakdown: gross sales, discounts, net sales and processed refunds.
-- Sales are recognized on completed orders; refunds are recognized when processed.
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
  v_gross numeric := 0;
  v_discounts numeric := 0;
  v_net_sales numeric := 0;
  v_delivery_fees numeric := 0;
  v_refunds numeric := 0;
  v_previous_net numeric := 0;
  v_order_count bigint := 0;
  v_refund_count bigint := 0;
begin
  if auth.uid() is null or not coalesce(public.is_admin(), false) then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if v_start is null or v_end is null or v_end < v_start then
    raise exception 'Invalid report date range' using errcode = '22023';
  end if;
  v_previous_start := v_start - (v_end - v_start);

  select coalesce(sum(o.subtotal_amount),0),
         coalesce(sum(o.discount_amount),0),
         coalesce(sum(o.subtotal_amount-o.discount_amount),0),
         coalesce(sum(o.delivery_fee),0),
         count(*)
    into v_gross,v_discounts,v_net_sales,v_delivery_fees,v_order_count
  from public.orders o
  where o.status='completed'
    and coalesce(o.completed_at,o.created_at)>=v_start
    and coalesce(o.completed_at,o.created_at)<=v_end;

  -- Refunds may belong to cancelled orders that are not recognized as sales.
  -- Show the cash outflow separately and never silently subtract it from sales.
  select coalesce(sum(r.amount),0),count(*)
    into v_refunds,v_refund_count
  from public.order_refunds r
  where r.status='refunded'
    and coalesce(r.processed_at,r.updated_at)>=v_start
    and coalesce(r.processed_at,r.updated_at)<=v_end;

  select coalesce(sum(o.subtotal_amount-o.discount_amount),0)
    into v_previous_net
  from public.orders o
  where o.status='completed'
    and coalesce(o.completed_at,o.created_at)>=v_previous_start
    and coalesce(o.completed_at,o.created_at)<v_start;

  select json_build_object(
    'id','sales_report','type','sales',
    'summary',json_build_object(
      'gross_sales',v_gross,
      'discount_amount',v_discounts,
      'net_sales',v_net_sales,
      'total_sales',v_net_sales,
      'delivery_fees',v_delivery_fees,
      'refund_amount',v_refunds,
      'refund_count',v_refund_count,
      'net_after_refunds',v_net_sales-v_refunds,
      'total_collected_before_refunds',v_net_sales+v_delivery_fees,
      'total_orders',v_order_count,
      'delivery_count',(select count(*) from public.orders o where o.status='completed' and o.order_type='delivery' and coalesce(o.completed_at,o.created_at)>=v_start and coalesce(o.completed_at,o.created_at)<=v_end),
      'pickup_count',(select count(*) from public.orders o where o.status='completed' and o.order_type='pickup' and coalesce(o.completed_at,o.created_at)>=v_start and coalesce(o.completed_at,o.created_at)<=v_end),
      'dine_in_count',(select count(*) from public.orders o where o.status='completed' and o.order_type='dine_in' and coalesce(o.completed_at,o.created_at)>=v_start and coalesce(o.completed_at,o.created_at)<=v_end),
      'previous_period_sales',v_previous_net,
      'growth_percentage',case when v_previous_net=0 then case when v_net_sales=0 then 0 else 100 end else round(((v_net_sales-v_previous_net)/v_previous_net)*100,2) end
    ),
    'chart_data',(select coalesce(json_agg(json_build_object(
      'date',d.sale_date,'amount',d.net_sales,'gross_sales',d.gross_sales,
      'discount_amount',d.discount_amount,'net_sales',d.net_sales
    ) order by d.sale_date),'[]'::json)
      from (
        select to_char((coalesce(o.completed_at,o.created_at) at time zone 'Asia/Baku')::date,'YYYY-MM-DD') sale_date,
          sum(o.subtotal_amount) gross_sales,
          sum(o.discount_amount) discount_amount,
          sum(o.subtotal_amount-o.discount_amount) net_sales
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

revoke all on function public.get_sales_report(text,text) from public,anon;
grant execute on function public.get_sales_report(text,text) to authenticated;
