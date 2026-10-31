create or replace function public.get_report_reconciliation(start_date timestamptz, end_date timestamptz)
returns jsonb language plpgsql security invoker set search_path = ''
as $function$
declare v_result jsonb;
begin
  if auth.uid() is null or not coalesce(public.is_admin(), false) then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if start_date is null or end_date is null or end_date < start_date then
    raise exception 'Invalid report date range' using errcode = '22023';
  end if;
  with scoped_orders as (
    select o.* from public.orders o where o.created_at >= start_date and o.created_at <= end_date
  ),
  item_totals as (
    select oi.order_id, count(*)::bigint item_count, coalesce(sum(oi.total_price),0)::numeric items_total,
      count(distinct oi.product_id) filter (where not exists(select 1 from public.product_recipes r where r.product_id=oi.product_id))::bigint products_without_recipe
    from public.order_items oi join scoped_orders o on o.id=oi.order_id group by oi.order_id
  ),
  payment_totals as (
    select p.order_id, coalesce(sum(p.amount) filter(where p.status='received'),0)::numeric received_total,
      count(*) filter(where p.status='received')::bigint received_count,
      count(*) filter(where p.status='voided')::bigint voided_count
    from public.order_payments p join scoped_orders o on o.id=p.order_id group by p.order_id
  ),
  refund_totals as (
    select r.order_id, coalesce(sum(r.amount) filter(where r.status='refunded'),0)::numeric refunded_total
    from public.order_refunds r join scoped_orders o on o.id=r.order_id group by r.order_id
  ),
  expected_usage as (
    select oi.order_id,r.material_id,sum(r.quantity_per_product*oi.quantity)::numeric(14,3) expected_quantity
    from public.order_items oi join scoped_orders o on o.id=oi.order_id
    join public.product_recipes r on r.product_id=oi.product_id
    where o.status in ('preparing','ready','out_for_delivery','completed')
       or (o.status='cancelled' and exists(select 1 from public.inventory_transactions tx where tx.order_id=o.id and tx.transaction_type='order_usage'))
    group by oi.order_id,r.material_id
  ),
  actual_usage as (
    select tx.order_id,tx.material_id,sum(abs(tx.quantity_delta))::numeric(14,3) actual_quantity,
      sum(abs(tx.total_cost))::numeric(14,2) actual_cost,count(*)::bigint movement_count
    from public.inventory_transactions tx join scoped_orders o on o.id=tx.order_id
    where tx.transaction_type='order_usage' group by tx.order_id,tx.material_id
  ),
  usage_comparison as (
    select coalesce(e.order_id,a.order_id) order_id,coalesce(e.material_id,a.material_id) material_id,
      coalesce(m.name,'ماده حذف‌شده/نامشخص') material_name,coalesce(m.unit,'') unit,
      coalesce(e.expected_quantity,0)::numeric expected_quantity,coalesce(a.actual_quantity,0)::numeric actual_quantity,
      (coalesce(a.actual_quantity,0)-coalesce(e.expected_quantity,0))::numeric quantity_difference,
      coalesce(a.actual_cost,0)::numeric actual_cost,
      case when e.order_id is null then 'مصرف ثبت‌شده بدون دستور مصرف'
        when a.order_id is null then 'مصرف انبار ثبت نشده'
        when abs(coalesce(a.actual_quantity,0)-coalesce(e.expected_quantity,0))>0.001 then 'مغایرت مقدار مصرف'
        else 'مطابق' end reconciliation_status
    from expected_usage e full join actual_usage a on a.order_id=e.order_id and a.material_id=e.material_id
    left join public.inventory_materials m on m.id=coalesce(e.material_id,a.material_id)
  ),
  order_rows as (
    select o.id order_id,o.daily_queue_number,o.created_at,o.status,
      coalesce(o.total_amount,0)::numeric order_total,coalesce(o.subtotal_amount,0)::numeric subtotal_amount,
      coalesce(i.items_total,0)::numeric items_total,coalesce(i.item_count,0)::bigint item_count,
      coalesce(i.products_without_recipe,0)::bigint products_without_recipe,
      coalesce(p.received_total,0)::numeric received_total,coalesce(r.refunded_total,0)::numeric refunded_total,
      (coalesce(p.received_total,0)-coalesce(r.refunded_total,0))::numeric net_received,
      (coalesce(o.total_amount,0)-coalesce(p.received_total,0)+coalesce(r.refunded_total,0))::numeric payment_difference,
      coalesce(p.received_count,0)::bigint received_payment_count,coalesce(p.voided_count,0)::bigint voided_payment_count,
      (select count(*) from usage_comparison u where u.order_id=o.id and u.reconciliation_status<>'مطابق')::bigint inventory_issue_count,
      case
        when coalesce(i.item_count,0)=0 then 'سفارش بدون قلم'
        when abs(coalesce(o.subtotal_amount,0)-coalesce(i.items_total,0))>1 then 'مغایرت جمع اقلام و مبلغ پایه'
        when coalesce(o.status,'')='completed' and abs(coalesce(o.total_amount,0)-coalesce(p.received_total,0)+coalesce(r.refunded_total,0))>1 then 'مغایرت مبلغ سفارش و پرداخت خالص'
        when o.status='cancelled' and (coalesce(p.received_total,0)-coalesce(r.refunded_total,0))>1 then 'وجه سفارش لغوشده بازپرداخت نشده'
        when coalesce(o.total_amount,0)-coalesce(p.received_total,0)+coalesce(r.refunded_total,0)<-1 then 'دریافت بیش از مبلغ سفارش'
        when coalesce(i.products_without_recipe,0)>0 and o.status in ('preparing','ready','out_for_delivery','completed') then 'غذا بدون دستور مصرف'
        when (select count(*) from usage_comparison u where u.order_id=o.id and u.reconciliation_status<>'مطابق')>0 then 'مغایرت گردش انبار'
        when o.status not in ('completed','cancelled') and coalesce(o.total_amount,0)-coalesce(p.received_total,0)+coalesce(r.refunded_total,0)>1 then 'مانده پرداخت (عادی)'
        else 'مطابق'
      end reconciliation_status
    from scoped_orders o left join item_totals i on i.order_id=o.id
    left join payment_totals p on p.order_id=o.id left join refund_totals r on r.order_id=o.id
  ),
  transaction_rows as (
    select tx.id transaction_id,tx.created_at,tx.transaction_type,tx.material_id,
      coalesce(m.name,'ماده حذف‌شده/نامشخص') material_name,tx.quantity_delta,tx.unit_cost,tx.total_cost,tx.order_id,
      o.daily_queue_number,o.status order_status,tx.reason,
      case when tx.transaction_type='order_usage' and tx.order_id is null then 'مصرف بدون سفارش'
        when tx.order_id is not null and o.id is null then 'سفارش مرتبط ناموجود'
        when tx.transaction_type='order_usage' and o.status='cancelled' then 'مصرف سفارش لغوشده؛ بررسی لازم'
        when tx.order_id is not null and tx.transaction_type<>'order_usage' then 'گردش دستی مرتبط با سفارش'
        else 'ثبت‌شده' end reconciliation_status
    from public.inventory_transactions tx
    left join public.orders o on o.id=tx.order_id
    left join public.inventory_materials m on m.id=tx.material_id
    where (tx.created_at>=start_date and tx.created_at<=end_date)
       or (tx.order_id in (select id from scoped_orders) and tx.transaction_type='order_usage')
  )
  select jsonb_build_object(
    'id','report_reconciliation','type','reconciliation',
    'summary',jsonb_build_object(
      'orders_checked',(select count(*) from order_rows),
      'orders_with_issues',(select count(*) from order_rows where reconciliation_status not in ('مطابق','مانده پرداخت (عادی)')),
      'payment_mismatches',(select count(*) from order_rows where (status='completed' and abs(payment_difference)>1) or (status='cancelled' and net_received>1) or payment_difference < -1),
      'orders_without_items',(select count(*) from order_rows where item_count=0),
      'orders_without_recipe',(select count(*) from order_rows where products_without_recipe>0),
      'inventory_mismatches',(select count(*) from usage_comparison where reconciliation_status<>'مطابق'),
      'inventory_transactions',(select count(*) from transaction_rows),
      'unlinked_inventory_usage',(select count(*) from transaction_rows where transaction_type='order_usage' and order_id is null),
      'total_order_value',(select coalesce(sum(order_total),0) from order_rows),
      'total_net_received',(select coalesce(sum(net_received),0) from order_rows),
      'payment_variance',(select coalesce(sum(payment_difference),0) from order_rows)
    ),
    'chart_data',jsonb_build_array(jsonb_build_object(
      'orders',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from order_rows x),'[]'::jsonb),
      'inventory',coalesce((select jsonb_agg(to_jsonb(x) order by x.order_id,x.material_name) from usage_comparison x),'[]'::jsonb),
      'transactions',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from transaction_rows x),'[]'::jsonb)
    )),
    'start_date',start_date,'end_date',end_date,'created_at',pg_catalog.now()
  ) into v_result;
  return v_result;
end;
$function$;
revoke all on function public.get_report_reconciliation(timestamptz,timestamptz) from public,anon;
grant execute on function public.get_report_reconciliation(timestamptz,timestamptz) to authenticated;