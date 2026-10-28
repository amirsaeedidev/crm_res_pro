-- CRM additions: monetary customer wallet, stock/recipes, persistent admin notifications,
-- configurable receipts, daily queue number and stock deductions on the first move to preparing.
-- Safe to apply more than once.

create table if not exists public.customer_wallets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  balance numeric(14,2) not null default 0 check (balance >= 0),
  currency text not null default 'IRR' check (currency in ('IRR','IRT')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.customer_wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  wallet_id uuid not null references public.customer_wallets(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  amount_delta numeric(14,2) not null check (amount_delta <> 0),
  balance_after numeric(14,2) not null check (balance_after >= 0),
  transaction_type text not null check (transaction_type in ('top_up','adjustment','order_payment','refund')),
  reason text not null,
  order_id uuid null references public.orders(id) on delete set null,
  performed_by uuid null references auth.users(id) on delete set null,
  idempotency_key text null unique,
  created_at timestamptz not null default now()
);

create index if not exists customer_wallet_transactions_user_created_idx
  on public.customer_wallet_transactions(user_id, created_at desc);
create index if not exists customer_wallet_transactions_wallet_created_idx
  on public.customer_wallet_transactions(wallet_id, created_at desc);

create table if not exists public.inventory_materials (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 120),
  sku text null unique,
  unit text not null check (unit in ('g','kg','ml','l','unit','pack','box')),
  quantity_on_hand numeric(14,3) not null default 0 check (quantity_on_hand >= 0),
  unit_cost numeric(14,2) not null default 0 check (unit_cost >= 0),
  reorder_level numeric(14,3) not null default 0 check (reorder_level >= 0),
  is_active boolean not null default true,
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists inventory_materials_active_name_idx
  on public.inventory_materials(is_active, name);
create index if not exists inventory_materials_low_stock_idx
  on public.inventory_materials(quantity_on_hand, reorder_level)
  where is_active = true;

create table if not exists public.product_recipes (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  material_id uuid not null references public.inventory_materials(id) on delete restrict,
  quantity_per_product numeric(14,3) not null check (quantity_per_product > 0),
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(product_id, material_id)
);
create index if not exists product_recipes_material_idx on public.product_recipes(material_id);
create index if not exists product_recipes_product_idx on public.product_recipes(product_id);

create table if not exists public.inventory_transactions (
  id uuid primary key default gen_random_uuid(),
  material_id uuid not null references public.inventory_materials(id) on delete restrict,
  transaction_type text not null check (transaction_type in ('purchase','adjustment','order_usage','waste','return')),
  quantity_delta numeric(14,3) not null check (quantity_delta <> 0),
  unit_cost numeric(14,2) not null default 0 check (unit_cost >= 0),
  total_cost numeric(14,2) not null default 0 check (total_cost >= 0),
  order_id uuid null references public.orders(id) on delete set null,
  reason text not null,
  performed_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists inventory_transactions_material_created_idx
  on public.inventory_transactions(material_id, created_at desc);
create index if not exists inventory_transactions_order_idx
  on public.inventory_transactions(order_id) where order_id is not null;

create table if not exists public.receipt_settings (
  id text primary key default 'main' check (id = 'main'),
  store_name text not null default 'رستوران',
  logo_url text not null default '',
  store_phone text not null default '',
  store_address text not null default '',
  header_text text not null default '',
  footer_text text not null default 'با تشکر از خرید شما',
  paper_size text not null default 'a4' check (paper_size in ('a4','roll_80','roll_58')),
  show_logo boolean not null default true,
  show_date boolean not null default true,
  show_customer boolean not null default true,
  show_phone boolean not null default true,
  show_order_type boolean not null default true,
  show_table_number boolean not null default true,
  show_queue_number boolean not null default true,
  show_discount boolean not null default true,
  show_notes boolean not null default true,
  updated_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
insert into public.receipt_settings(id) values ('main') on conflict (id) do nothing;

create table if not exists public.admin_notifications (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null default '',
  notification_type text not null default 'general',
  entity_table text null,
  entity_id uuid null,
  is_read boolean not null default false,
  read_at timestamptz null,
  created_at timestamptz not null default now()
);
create index if not exists admin_notifications_created_idx
  on public.admin_notifications(created_at desc);
create index if not exists admin_notifications_unread_idx
  on public.admin_notifications(created_at desc) where is_read = false;

alter table public.orders add column if not exists daily_queue_number integer null;
create index if not exists orders_created_queue_idx on public.orders(created_at desc, daily_queue_number);

-- Existing and future customers get a monetary wallet separate from loyalty points.
insert into public.customer_wallets(user_id)
select p.id from public.profiles p where p.role = 'customer'
on conflict (user_id) do nothing;

create or replace function public.ensure_customer_wallet()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.role = 'customer' then
    insert into public.customer_wallets(user_id) values (new.id) on conflict (user_id) do nothing;
  end if;
  return new;
end;
$$;
drop trigger if exists profiles_ensure_customer_wallet on public.profiles;
create trigger profiles_ensure_customer_wallet after insert or update of role on public.profiles
for each row execute function public.ensure_customer_wallet();
revoke all on function public.ensure_customer_wallet() from public, anon, authenticated;

create or replace function public.assign_daily_queue_number()
returns trigger language plpgsql set search_path = '' as $$
declare v_date date;
begin
  if new.created_at is null then new.created_at := pg_catalog.now(); end if;
  v_date := (new.created_at at time zone 'UTC')::date;
  if new.daily_queue_number is null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('daily-queue-' || v_date::text));
    select coalesce(max(o.daily_queue_number), 0) + 1
      into new.daily_queue_number
      from public.orders o
     where (o.created_at at time zone 'UTC')::date = v_date;
  end if;
  return new;
end;
$$;
drop trigger if exists orders_assign_daily_queue_number on public.orders;
create trigger orders_assign_daily_queue_number before insert on public.orders
for each row execute function public.assign_daily_queue_number();
revoke all on function public.assign_daily_queue_number() from public, anon, authenticated;

create or replace function public.admin_adjust_customer_wallet(
  p_user_id uuid,
  p_amount_delta numeric,
  p_reason text,
  p_transaction_type text default 'adjustment'
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_wallet public.customer_wallets%rowtype;
  v_new_balance numeric(14,2);
  v_type text;
  v_reason text;
begin
  if not public.is_admin() then raise exception 'Administrator access required' using errcode = '42501'; end if;
  if p_user_id is null then raise exception 'Customer id is required' using errcode = '22023'; end if;
  if p_amount_delta is null or p_amount_delta = 0 then raise exception 'Amount cannot be zero' using errcode = '22023'; end if;
  if abs(p_amount_delta) > 100000000000 then raise exception 'Amount is out of allowed range' using errcode = '22023'; end if;
  v_reason := pg_catalog.btrim(coalesce(p_reason, ''));
  if v_reason = '' then raise exception 'Reason is required' using errcode = '22023'; end if;
  v_type := coalesce(nullif(pg_catalog.btrim(p_transaction_type), ''), 'adjustment');
  if v_type not in ('top_up','adjustment','refund') then raise exception 'Unsupported wallet transaction type' using errcode = '22023'; end if;
  insert into public.customer_wallets(user_id, balance) values (p_user_id, 0) on conflict (user_id) do nothing;
  select * into v_wallet from public.customer_wallets where user_id = p_user_id for update;
  v_new_balance := v_wallet.balance + p_amount_delta;
  if v_new_balance < 0 then raise exception 'Wallet balance cannot be negative' using errcode = '22023'; end if;
  update public.customer_wallets set balance = v_new_balance, updated_at = pg_catalog.now() where id = v_wallet.id;
  insert into public.customer_wallet_transactions(wallet_id,user_id,amount_delta,balance_after,transaction_type,reason,performed_by)
  values (v_wallet.id,p_user_id,p_amount_delta,v_new_balance,v_type,v_reason,(select auth.uid()));
  return pg_catalog.jsonb_build_object('wallet_id',v_wallet.id,'user_id',p_user_id,'balance',v_new_balance);
end;
$$;
revoke all on function public.admin_adjust_customer_wallet(uuid,numeric,text,text) from public, anon;
grant execute on function public.admin_adjust_customer_wallet(uuid,numeric,text,text) to authenticated;

create or replace function public.admin_receive_inventory(
  p_material_id uuid, p_quantity numeric, p_unit_cost numeric, p_reason text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_material public.inventory_materials%rowtype; v_new_stock numeric(14,3); v_new_cost numeric(14,2); v_reason text;
begin
  if not public.is_admin() then raise exception 'Administrator access required' using errcode='42501'; end if;
  if p_material_id is null or p_quantity is null or p_quantity <= 0 then raise exception 'Quantity must be positive' using errcode='22023'; end if;
  if p_unit_cost is null or p_unit_cost < 0 then raise exception 'Unit cost cannot be negative' using errcode='22023'; end if;
  v_reason := pg_catalog.btrim(coalesce(p_reason,''));
  if v_reason = '' then raise exception 'Purchase reason is required' using errcode='22023'; end if;
  select * into v_material from public.inventory_materials where id=p_material_id for update;
  if not found then raise exception 'Material not found' using errcode='P0002'; end if;
  v_new_stock := v_material.quantity_on_hand + p_quantity;
  if v_new_stock > 1000000000 then raise exception 'Stock quantity is out of range' using errcode='22023'; end if;
  v_new_cost := case when v_new_stock = 0 then p_unit_cost else round(((v_material.quantity_on_hand * v_material.unit_cost) + (p_quantity * p_unit_cost)) / v_new_stock, 2) end;
  update public.inventory_materials set quantity_on_hand=v_new_stock, unit_cost=v_new_cost, updated_at=pg_catalog.now() where id=p_material_id;
  insert into public.inventory_transactions(material_id,transaction_type,quantity_delta,unit_cost,total_cost,reason,performed_by)
  values(p_material_id,'purchase',p_quantity,p_unit_cost,round(p_quantity*p_unit_cost,2),v_reason,(select auth.uid()));
  return pg_catalog.jsonb_build_object('material_id',p_material_id,'quantity_on_hand',v_new_stock,'unit_cost',v_new_cost);
end;
$$;
revoke all on function public.admin_receive_inventory(uuid,numeric,numeric,text) from public, anon;
grant execute on function public.admin_receive_inventory(uuid,numeric,numeric,text) to authenticated;

create or replace function public.admin_adjust_inventory(
  p_material_id uuid, p_quantity_delta numeric, p_reason text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_material public.inventory_materials%rowtype; v_new_stock numeric(14,3); v_reason text;
begin
  if not public.is_admin() then raise exception 'Administrator access required' using errcode='42501'; end if;
  if p_material_id is null or p_quantity_delta is null or p_quantity_delta = 0 then raise exception 'Quantity delta cannot be zero' using errcode='22023'; end if;
  v_reason := pg_catalog.btrim(coalesce(p_reason,''));
  if v_reason = '' then raise exception 'Reason is required' using errcode='22023'; end if;
  select * into v_material from public.inventory_materials where id=p_material_id for update;
  if not found then raise exception 'Material not found' using errcode='P0002'; end if;
  v_new_stock := v_material.quantity_on_hand + p_quantity_delta;
  if v_new_stock < 0 then raise exception 'Adjustment would make stock negative' using errcode='22023'; end if;
  update public.inventory_materials set quantity_on_hand=v_new_stock, updated_at=pg_catalog.now() where id=p_material_id;
  insert into public.inventory_transactions(material_id,transaction_type,quantity_delta,unit_cost,total_cost,reason,performed_by)
  values(p_material_id,'adjustment',p_quantity_delta,v_material.unit_cost,round(abs(p_quantity_delta)*v_material.unit_cost,2),v_reason,(select auth.uid()));
  return pg_catalog.jsonb_build_object('material_id',p_material_id,'quantity_on_hand',v_new_stock);
end;
$$;
revoke all on function public.admin_adjust_inventory(uuid,numeric,text) from public, anon;
grant execute on function public.admin_adjust_inventory(uuid,numeric,text) to authenticated;

-- Deduct recipe components atomically once when an order first enters preparation.
create or replace function public.consume_order_recipe_inventory()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_recipe record; v_stock numeric(14,3); v_cost numeric(14,2);
begin
  if new.status = 'preparing' and old.status is distinct from new.status then
    for v_recipe in
      select r.material_id, sum(r.quantity_per_product * oi.quantity)::numeric(14,3) as use_quantity
        from public.order_items oi join public.product_recipes r on r.product_id=oi.product_id
       where oi.order_id=new.id
       group by r.material_id order by r.material_id
    loop
      select quantity_on_hand, unit_cost into v_stock, v_cost
        from public.inventory_materials where id=v_recipe.material_id and is_active=true for update;
      if not found then raise exception 'Recipe material % does not exist or is inactive', v_recipe.material_id using errcode='22023'; end if;
      if v_stock < v_recipe.use_quantity then
        raise exception 'Insufficient stock for material %. Available %, required %', v_recipe.material_id, v_stock, v_recipe.use_quantity using errcode='22023';
      end if;
      update public.inventory_materials set quantity_on_hand=quantity_on_hand-v_recipe.use_quantity, updated_at=pg_catalog.now() where id=v_recipe.material_id;
      insert into public.inventory_transactions(material_id,transaction_type,quantity_delta,unit_cost,total_cost,order_id,reason)
      values(v_recipe.material_id,'order_usage',-v_recipe.use_quantity,v_cost,round(v_recipe.use_quantity*v_cost,2),new.id,'مصرف مواد اولیه سفارش #'||coalesce(new.daily_queue_number::text, left(new.id::text,8)));
    end loop;
  end if;
  return new;
end;
$$;
drop trigger if exists orders_consume_recipe_inventory on public.orders;
create trigger orders_consume_recipe_inventory before update of status on public.orders
for each row execute function public.consume_order_recipe_inventory();
revoke all on function public.consume_order_recipe_inventory() from public, anon, authenticated;

create or replace function public.create_admin_notification_for_row()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_row jsonb := pg_catalog.to_jsonb(new); v_title text; v_body text; v_type text;
begin
  if tg_table_name = 'orders' then
    v_title := 'سفارش جدید'; v_type := 'new_order';
    v_body := 'سفارش #'||coalesce(v_row->>'daily_queue_number',left(coalesce(v_row->>'id',''),8))||' ثبت شد؛ مبلغ: '||coalesce(v_row->>'total_amount','0');
  elsif tg_table_name = 'reservations' then
    v_title := 'رزرو جدید'; v_type := 'new_reservation';
    v_body := 'رزرو جدید ثبت شد؛ تعداد مهمان: '||coalesce(v_row->>'guest_count','—');
  elsif tg_table_name = 'profiles' and coalesce(v_row->>'role','') = 'customer' then
    v_title := 'مشتری جدید'; v_type := 'new_customer';
    v_body := pg_catalog.concat_ws(' ',coalesce(v_row->>'first_name',''),coalesce(v_row->>'last_name',''));
  elsif tg_table_name = 'tickets' then
    v_title := 'تیکت جدید'; v_type := 'new_ticket';
    v_body := coalesce(v_row->>'subject','درخواست پشتیبانی جدید');
  else
    return new;
  end if;
  insert into public.admin_notifications(title,body,notification_type,entity_table,entity_id)
  values(v_title,coalesce(nullif(v_body,''),v_title),v_type,tg_table_name,nullif(v_row->>'id','')::uuid);
  return new;
end;
$$;
revoke all on function public.create_admin_notification_for_row() from public, anon, authenticated;
drop trigger if exists orders_notify_admins on public.orders;
create trigger orders_notify_admins after insert on public.orders for each row execute function public.create_admin_notification_for_row();
drop trigger if exists reservations_notify_admins on public.reservations;
create trigger reservations_notify_admins after insert on public.reservations for each row execute function public.create_admin_notification_for_row();
drop trigger if exists profiles_notify_admins on public.profiles;
create trigger profiles_notify_admins after insert on public.profiles for each row execute function public.create_admin_notification_for_row();
drop trigger if exists tickets_notify_admins on public.tickets;
create trigger tickets_notify_admins after insert on public.tickets for each row execute function public.create_admin_notification_for_row();

-- Security invoker means the view obeys the base tables' RLS policies.
create or replace view public.customer_wallets_view with (security_invoker = true) as
select w.id, w.user_id, w.balance, w.currency, w.created_at, w.updated_at,
       coalesce(nullif(pg_catalog.btrim(pg_catalog.concat_ws(' ',p.first_name,p.last_name)),''),'مشتری بدون نام') as customer_name,
       coalesce(p.phone,'') as customer_phone, p.email
  from public.customer_wallets w join public.profiles p on p.id=w.user_id;

-- Enable and restrict RLS on all newly exposed tables.
DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['customer_wallets','customer_wallet_transactions','inventory_materials','product_recipes','inventory_transactions','receipt_settings','admin_notifications'] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t||'_admin_all', t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR ALL TO authenticated USING ((select public.is_admin())) WITH CHECK ((select public.is_admin()))', t||'_admin_all', t);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON public.%I TO authenticated', t);
  END LOOP;
END $$;
GRANT SELECT ON public.customer_wallets_view TO authenticated;

-- Retain authenticated RPC use while blocking unauthenticated execution. Function bodies still enforce admin roles.
REVOKE EXECUTE ON FUNCTION public.admin_adjust_loyalty_points(uuid,integer,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_create_sms_campaign(text,uuid[],text,text,text[],jsonb) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_get_ticket_counts() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_queue_test_sms(text,text,text,text[]) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_reply_to_ticket(uuid,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_save_sms_settings(boolean,boolean,text,text,text,text,text,text,boolean,boolean,boolean,boolean,integer,integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_customer_distribution() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_dashboard_stats() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_kpi_statistics(text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_sales_report(text,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_top_products(integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_admin() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.place_order(text,jsonb,uuid,text,integer,uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_adjust_loyalty_points(uuid,integer,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_sms_campaign(text,uuid[],text,text,text[],jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_ticket_counts() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_queue_test_sms(text,text,text,text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reply_to_ticket(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_save_sms_settings(boolean,boolean,text,text,text,text,text,text,boolean,boolean,boolean,boolean,integer,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_customer_distribution() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_dashboard_stats() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_kpi_statistics(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_sales_report(text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_top_products(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.place_order(text,jsonb,uuid,text,integer,uuid,text,text) TO authenticated;

-- Make persistent admin notifications available through Supabase Realtime.
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname='supabase_realtime')
     AND NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='admin_notifications') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.admin_notifications;
  END IF;
END $$;
