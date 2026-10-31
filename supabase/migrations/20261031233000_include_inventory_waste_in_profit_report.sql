-- Include recorded inventory waste in estimated operating profit.
-- Purchased ingredients remain a separate disclosure to avoid double-counting
-- inventory purchases with actual consumption and waste.
create or replace function public.get_financial_report(
  start_date timestamp with time zone,
  end_date timestamp with time zone
)
returns json
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_revenue numeric := 0;
  v_orders bigint := 0;
  v_cogs numeric := 0;
  v_waste_cost numeric := 0;
  v_expenses numeric := 0;
  v_ingredient_purchases numeric := 0;
  v_expense_count bigint := 0;
  v_operating_expense_count bigint := 0;
  v_total_costs numeric := 0;
  v_profit numeric := 0;
begin
  if auth.uid() is null or not coalesce(public.is_admin(), false) then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if start_date is null or end_date is null or end_date < start_date then
    raise exception 'Invalid report date range' using errcode = '22023';
  end if;

  select coalesce(sum(o.total_amount), 0), count(*)
    into v_revenue, v_orders
  from public.orders o
  where o.status = 'completed'
    and coalesce(o.completed_at, o.created_at) >= start_date
    and coalesce(o.completed_at, o.created_at) <= end_date;

  select coalesce(sum(abs(tx.total_cost)), 0)
    into v_cogs
  from public.inventory_transactions tx
  where tx.transaction_type = 'order_usage'
    and tx.created_at >= start_date
    and tx.created_at <= end_date;

  select coalesce(sum(abs(tx.total_cost)), 0)
    into v_waste_cost
  from public.inventory_transactions tx
  where tx.transaction_type = 'waste'
    and tx.created_at >= start_date
    and tx.created_at <= end_date;

  select
    coalesce(sum(e.amount) filter (where e.category <> 'ingredients_purchase'), 0),
    coalesce(sum(e.amount) filter (where e.category = 'ingredients_purchase'), 0),
    count(*),
    count(*) filter (where e.category <> 'ingredients_purchase')
  into v_expenses, v_ingredient_purchases, v_expense_count, v_operating_expense_count
  from public.restaurant_expenses e
  where e.occurred_on >= (start_date at time zone 'Asia/Baku')::date
    and e.occurred_on <= (end_date at time zone 'Asia/Baku')::date;

  v_total_costs := v_cogs + v_waste_cost + v_expenses;
  v_profit := v_revenue - v_total_costs;

  return json_build_object(
    'id', 'financial_report',
    'type', 'financial',
    'summary', json_build_object(
      'revenue', v_revenue,
      'completed_orders', v_orders,
      'inventory_cost', v_cogs,
      'waste_cost', v_waste_cost,
      'operating_expenses', v_expenses,
      'ingredient_purchase_expenses', v_ingredient_purchases,
      'total_costs', v_total_costs,
      'estimated_profit', v_profit,
      'profit_margin_percent', case when v_revenue > 0 then round((v_profit / v_revenue) * 100, 2) else 0 end,
      'expense_count', v_expense_count,
      'operating_expense_count', v_operating_expense_count,
      'cost_data_note', 'Estimated operating profit includes recipe consumption, recorded inventory waste, and operating expenses. Ingredient purchases are shown separately and are not double-counted until consumed or wasted.'
    ),
    'chart_data', json_build_array(
      json_build_object('label', 'فروش', 'amount', v_revenue),
      json_build_object('label', 'مواد مصرف‌شده در سفارش‌ها', 'amount', v_cogs),
      json_build_object('label', 'ضایعات مواد اولیه', 'amount', v_waste_cost),
      json_build_object('label', 'هزینه‌های عملیاتی', 'amount', v_expenses),
      json_build_object('label', 'خرید مواد (جدا از سود)', 'amount', v_ingredient_purchases),
      json_build_object('label', 'سود عملیاتی تخمینی', 'amount', v_profit)
    ),
    'start_date', start_date,
    'end_date', end_date,
    'created_at', pg_catalog.now()
  );
end;
$function$;

revoke all on function public.get_financial_report(timestamptz, timestamptz) from public, anon;
grant execute on function public.get_financial_report(timestamptz, timestamptz) to authenticated;
