-- Dish profitability and cash register reconciliation.
create table if not exists public.cash_register_closings (
 id uuid primary key default gen_random_uuid(),
 business_date date not null,
 shift_label text not null default 'شیفت اصلی',
 opening_cash numeric(14,2) not null default 0 check(opening_cash>=0),
 counted_cash numeric(14,2) not null check(counted_cash>=0),
 expected_cash numeric(14,2) not null default 0 check(expected_cash>=0),
 note text, recorded_by uuid not null references auth.users(id), created_at timestamptz not null default now()
);
create index if not exists cash_register_closings_business_date_idx on public.cash_register_closings(business_date desc);
alter table public.cash_register_closings enable row level security;
revoke all on public.cash_register_closings from public,anon,authenticated;
grant select,insert on public.cash_register_closings to authenticated;
drop policy if exists cash_register_closings_admin_select on public.cash_register_closings;
create policy cash_register_closings_admin_select on public.cash_register_closings for select to authenticated using(coalesce(public.is_admin(),false));
drop policy if exists cash_register_closings_admin_insert on public.cash_register_closings;
create policy cash_register_closings_admin_insert on public.cash_register_closings for insert to authenticated with check(coalesce(public.is_admin(),false) and recorded_by=(select auth.uid()));

create or replace function public.get_dish_profit_report(start_date timestamptz,end_date timestamptz)
returns json language plpgsql security invoker set search_path='' as $$
declare v_summary json; v_dishes json; v_daily json; v_monthly json;
begin
 if auth.uid() is null or not coalesce(public.is_admin(),false) then raise exception 'Administrator access required' using errcode='42501'; end if;
 if start_date is null or end_date is null or end_date<start_date then raise exception 'Invalid report date range' using errcode='22023'; end if;
 with sales as (
  select oi.product_id,p.name product_name,sum(oi.quantity)::numeric quantity,sum(oi.total_price) gross_revenue,
   sum(oi.total_price*case when coalesce(o.subtotal_amount,0)>0 then greatest(o.subtotal_amount-coalesce(o.discount_amount,0),0)/o.subtotal_amount else 1 end) net_revenue
  from public.order_items oi join public.orders o on o.id=oi.order_id join public.products p on p.id=oi.product_id
  where o.status='completed' and coalesce(o.completed_at,o.created_at)>=start_date and coalesce(o.completed_at,o.created_at)<=end_date group by oi.product_id,p.name
 ), costs as (
  select pr.product_id,sum(pr.quantity_per_product*im.unit_cost) unit_cost from public.product_recipes pr join public.inventory_materials im on im.id=pr.material_id group by pr.product_id
 ), dish as (
  select s.*,coalesce(c.unit_cost,0) unit_cost,s.quantity*coalesce(c.unit_cost,0) total_cost,s.net_revenue-s.quantity*coalesce(c.unit_cost,0) gross_profit from sales s left join costs c on c.product_id=s.product_id
 )
 select coalesce(json_agg(json_build_object('product_id',product_id,'product_name',product_name,'quantity',quantity,'gross_revenue',gross_revenue,'net_revenue',net_revenue,'unit_cost',unit_cost,'total_cost',total_cost,'gross_profit',gross_profit,'profit_margin_percent',case when net_revenue>0 then round(gross_profit/net_revenue*100,2) else 0 end) order by gross_profit desc),'[]'::json) into v_dishes from dish;
 with d as (
  select (coalesce(o.completed_at,o.created_at) at time zone 'Asia/Baku')::date day,
   sum(oi.total_price*case when coalesce(o.subtotal_amount,0)>0 then greatest(o.subtotal_amount-coalesce(o.discount_amount,0),0)/o.subtotal_amount else 1 end) revenue,
   sum(oi.quantity*coalesce((select sum(pr.quantity_per_product*im.unit_cost) from public.product_recipes pr join public.inventory_materials im on im.id=pr.material_id where pr.product_id=oi.product_id),0)) cost
  from public.orders o join public.order_items oi on oi.order_id=o.id where o.status='completed' and coalesce(o.completed_at,o.created_at)>=start_date and coalesce(o.completed_at,o.created_at)<=end_date group by 1
 )
 select coalesce(json_agg(json_build_object('date',day,'revenue',revenue,'cost',cost,'profit',revenue-cost) order by day),'[]'::json) into v_daily from d;
 with m as (
  select date_trunc('month',coalesce(o.completed_at,o.created_at) at time zone 'Asia/Baku')::date month,
   sum(oi.total_price*case when coalesce(o.subtotal_amount,0)>0 then greatest(o.subtotal_amount-coalesce(o.discount_amount,0),0)/o.subtotal_amount else 1 end) revenue,
   sum(oi.quantity*coalesce((select sum(pr.quantity_per_product*im.unit_cost) from public.product_recipes pr join public.inventory_materials im on im.id=pr.material_id where pr.product_id=oi.product_id),0)) cost
  from public.orders o join public.order_items oi on oi.order_id=o.id where o.status='completed' and coalesce(o.completed_at,o.created_at)>=start_date and coalesce(o.completed_at,o.created_at)<=end_date group by 1
 )
 select coalesce(json_agg(json_build_object('month',month,'revenue',revenue,'cost',cost,'profit',revenue-cost) order by month),'[]'::json) into v_monthly from m;
 select json_build_object('dish_count',count(*),'total_quantity',coalesce(sum((x->>'quantity')::numeric),0),'total_revenue',coalesce(sum((x->>'net_revenue')::numeric),0),'total_cost',coalesce(sum((x->>'total_cost')::numeric),0),'total_profit',coalesce(sum((x->>'gross_profit')::numeric),0)) into v_summary from json_array_elements(v_dishes) x;
 return json_build_object('id','dish_profit_report','type','dish_profit','summary',v_summary,'chart_data',json_build_object('dishes',v_dishes,'daily',v_daily,'monthly',v_monthly),'start_date',start_date,'end_date',end_date,'created_at',now());
end; $$;
revoke all on function public.get_dish_profit_report(timestamptz,timestamptz) from public,anon;
grant execute on function public.get_dish_profit_report(timestamptz,timestamptz) to authenticated;

create or replace function public.record_cash_register_closing(p_business_date date,p_shift_label text,p_opening_cash numeric,p_counted_cash numeric,p_note text default null)
returns json language plpgsql security invoker set search_path='' as $$
declare v_expected numeric; v_id uuid;
begin
 if auth.uid() is null or not coalesce(public.is_admin(),false) then raise exception 'Administrator access required' using errcode='42501'; end if;
 if p_business_date is null or p_shift_label is null or btrim(p_shift_label)='' or p_opening_cash<0 or p_counted_cash<0 then raise exception 'Invalid cash closing values' using errcode='22023'; end if;
 select p_opening_cash+coalesce(sum(op.amount) filter(where lower(op.payment_method) in ('cash','نقدی','نقد')),0) into v_expected
 from public.order_payments op where op.status='received' and (op.received_at at time zone 'Asia/Baku')::date=p_business_date;
 insert into public.cash_register_closings(business_date,shift_label,opening_cash,counted_cash,expected_cash,note,recorded_by)
 values(p_business_date,p_shift_label,p_opening_cash,p_counted_cash,v_expected,p_note,auth.uid()) returning id into v_id;
 return json_build_object('id',v_id,'expected_cash',v_expected,'counted_cash',p_counted_cash,'variance',p_counted_cash-v_expected);
end; $$;
revoke all on function public.record_cash_register_closing(date,text,numeric,numeric,text) from public,anon;
grant execute on function public.record_cash_register_closing(date,text,numeric,numeric,text) to authenticated;

create or replace function public.get_payment_reconciliation_report(start_date timestamptz,end_date timestamptz)
returns json language plpgsql security invoker set search_path='' as $$
declare v_methods json; v_closings json; v_summary json;
begin
 if auth.uid() is null or not coalesce(public.is_admin(),false) then raise exception 'Administrator access required' using errcode='42501'; end if;
 if start_date is null or end_date is null or end_date<start_date then raise exception 'Invalid report date range' using errcode='22023'; end if;
 select coalesce(json_agg(json_build_object('payment_method',payment_method,'payment_count',payment_count,'amount',amount) order by amount desc),'[]'::json) into v_methods
 from(select coalesce(nullif(btrim(payment_method),''),'نامشخص') payment_method,count(*) payment_count,sum(amount) amount from public.order_payments where status='received' and received_at between start_date and end_date group by 1) p;
 select coalesce(json_agg(json_build_object('id',id,'business_date',business_date,'shift_label',shift_label,'opening_cash',opening_cash,'expected_cash',expected_cash,'counted_cash',counted_cash,'variance',counted_cash-expected_cash,'note',note,'created_at',created_at) order by business_date desc,created_at desc),'[]'::json) into v_closings
 from public.cash_register_closings where business_date between (start_date at time zone 'Asia/Baku')::date and (end_date at time zone 'Asia/Baku')::date;
 select json_build_object('total_received',coalesce(sum(amount),0),'payment_count',count(*),'cash_received',coalesce(sum(amount) filter(where lower(payment_method) in ('cash','نقدی','نقد')),0),'non_cash_received',coalesce(sum(amount) filter(where lower(payment_method) not in ('cash','نقدی','نقد')),0)) into v_summary
 from public.order_payments where status='received' and received_at between start_date and end_date;
 return json_build_object('id','payment_reconciliation_report','type','payment_reconciliation','summary',v_summary,'chart_data',json_build_object('methods',v_methods,'closings',v_closings),'start_date',start_date,'end_date',end_date,'created_at',now());
end; $$;
revoke all on function public.get_payment_reconciliation_report(timestamptz,timestamptz) from public,anon;
grant execute on function public.get_payment_reconciliation_report(timestamptz,timestamptz) to authenticated;
