-- Review and run manually in Supabase SQL Editor; Flutter does not execute this file.
-- Profit is estimated from completed-order revenue less recorded stock usage and recorded expenses.
begin;
create table if not exists public.restaurant_expenses (
 id uuid primary key default gen_random_uuid(),
 title text not null check(length(trim(title)) between 1 and 160),
 category text not null default 'other',
 amount numeric(14,2) not null check(amount > 0),
 expense_date date not null default current_date,
 notes text not null default '',
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now()
);
create index if not exists restaurant_expenses_date_idx on public.restaurant_expenses(expense_date desc);
alter table public.restaurant_expenses enable row level security;
drop policy if exists restaurant_expenses_admin_select on public.restaurant_expenses;
create policy restaurant_expenses_admin_select on public.restaurant_expenses for select to authenticated using ((select public.is_admin()));
drop policy if exists restaurant_expenses_admin_insert on public.restaurant_expenses;
create policy restaurant_expenses_admin_insert on public.restaurant_expenses for insert to authenticated with check ((select public.is_admin()) and created_by = (select auth.uid()));
drop policy if exists restaurant_expenses_admin_update on public.restaurant_expenses;
create policy restaurant_expenses_admin_update on public.restaurant_expenses for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
drop policy if exists restaurant_expenses_admin_delete on public.restaurant_expenses;
create policy restaurant_expenses_admin_delete on public.restaurant_expenses for delete to authenticated using ((select public.is_admin()));
grant select, insert, update, delete on public.restaurant_expenses to authenticated;

create or replace function public.get_financial_report(start_date timestamptz, end_date timestamptz)
returns json language plpgsql security invoker set search_path = '' as $$
declare
 v_revenue numeric := 0; v_orders bigint := 0; v_cogs numeric := 0;
 v_expenses numeric := 0; v_expense_count bigint := 0;
begin
 if not (select public.is_admin()) then raise exception 'Administrator access required' using errcode='42501'; end if;
 if start_date is null or end_date is null or end_date < start_date then raise exception 'Invalid report date range' using errcode='22023'; end if;
 select coalesce(sum(o.total_amount),0),count(*) into v_revenue,v_orders
 from public.orders o where o.status='completed' and o.created_at >= start_date and o.created_at <= end_date;
 select coalesce(sum(abs(tx.total_cost)),0) into v_cogs from public.inventory_transactions tx
 where tx.transaction_type='order_usage' and tx.created_at >= start_date and tx.created_at <= end_date;
 select coalesce(sum(e.amount),0),count(*) into v_expenses,v_expense_count from public.restaurant_expenses e
 where e.expense_date >= start_date::date and e.expense_date <= end_date::date;
 return json_build_object(
 'id','financial_report','type','financial',
 'summary',json_build_object('revenue',v_revenue,'completed_orders',v_orders,'inventory_cost',v_cogs,
 'operating_expenses',v_expenses,'total_costs',v_cogs+v_expenses,
 'estimated_profit',v_revenue-v_cogs-v_expenses,'expense_count',v_expense_count,
 'cost_data_note','Estimated only; depends on recorded recipes, stock usage and expenses.'),
 'chart_data',json_build_array(json_build_object('label','فروش','amount',v_revenue),
 json_build_object('label','هزینه مواد','amount',v_cogs),json_build_object('label','هزینه جاری','amount',v_expenses),
 json_build_object('label','سود تخمینی','amount',v_revenue-v_cogs-v_expenses)),
 'start_date',start_date,'end_date',end_date,'created_at',now());
end; $$;

create or replace function public.get_inventory_report(start_date timestamptz, end_date timestamptz)
returns json language plpgsql security invoker set search_path = '' as $$
declare
 v_materials bigint := 0; v_low bigint := 0; v_value numeric := 0;
 v_purchases numeric := 0; v_used numeric := 0; v_waste numeric := 0; v_returns numeric := 0; v_rows json := '[]'::json;
begin
 if not (select public.is_admin()) then raise exception 'Administrator access required' using errcode='42501'; end if;
 if start_date is null or end_date is null or end_date < start_date then raise exception 'Invalid report date range' using errcode='22023'; end if;
 select count(*),count(*) filter(where quantity_on_hand <= reorder_level),coalesce(sum(quantity_on_hand*unit_cost),0)
 into v_materials,v_low,v_value from public.inventory_materials where is_active=true;
 select coalesce(sum(case when transaction_type='purchase' then total_cost else 0 end),0),
 coalesce(sum(case when transaction_type='order_usage' then abs(total_cost) else 0 end),0),
 coalesce(sum(case when transaction_type='waste' then abs(total_cost) else 0 end),0),
 coalesce(sum(case when transaction_type='return' then abs(total_cost) else 0 end),0)
 into v_purchases,v_used,v_waste,v_returns from public.inventory_transactions
 where created_at >= start_date and created_at <= end_date;
 select coalesce(json_agg(json_build_object('material_name',d.name,'unit',d.unit,
 'quantity_on_hand',d.quantity_on_hand,'unit_cost',d.unit_cost,'stock_value',d.stock_value,
 'reorder_level',d.reorder_level,'is_low_stock',d.is_low_stock) order by d.is_low_stock desc,d.stock_value desc),'[]'::json)
 into v_rows from (select name,unit,quantity_on_hand,unit_cost,quantity_on_hand*unit_cost stock_value,
 reorder_level,quantity_on_hand <= reorder_level is_low_stock from public.inventory_materials where is_active=true) d;
 return json_build_object('id','inventory_report','type','inventory',
 'summary',json_build_object('active_materials',v_materials,'low_stock_materials',v_low,'stock_value',v_value,
 'purchases_cost',v_purchases,'consumption_cost',v_used,'waste_cost',v_waste,'return_cost',v_returns),
 'chart_data',v_rows,'start_date',start_date,'end_date',end_date,'created_at',now());
end; $$;
revoke all on function public.get_financial_report(timestamptz,timestamptz) from public,anon;
revoke all on function public.get_inventory_report(timestamptz,timestamptz) from public,anon;
grant execute on function public.get_financial_report(timestamptz,timestamptz) to authenticated;
grant execute on function public.get_inventory_report(timestamptz,timestamptz) to authenticated;
commit;
