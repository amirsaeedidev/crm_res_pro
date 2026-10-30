-- Loyalty rules, point expiry and point-to-discount conversion.
begin;

create table if not exists public.loyalty_program_settings (
  id boolean primary key default true check (id),
  is_enabled boolean not null default true,
  earn_amount_toman numeric(14,0) not null default 100000 check (earn_amount_toman > 0),
  earn_points integer not null default 1 check (earn_points > 0),
  point_value_toman numeric(14,0) not null default 1000 check (point_value_toman > 0),
  minimum_redeem_points integer not null default 10 check (minimum_redeem_points > 0),
  maximum_discount_percent numeric(5,2) not null default 30 check (maximum_discount_percent between 1 and 100),
  expiry_days integer not null default 365 check (expiry_days between 1 and 3650),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);
insert into public.loyalty_program_settings(id) values(true) on conflict(id) do nothing;

alter table public.loyalty_transactions
  add column if not exists expires_at timestamptz,
  add column if not exists expired_at timestamptz;

update public.loyalty_transactions t
set expires_at = t.created_at + make_interval(days => (select expiry_days from public.loyalty_program_settings where id=true))
where t.transaction_type='earned' and t.expires_at is null;

create index if not exists loyalty_transactions_expiry_idx
  on public.loyalty_transactions(expires_at, wallet_id)
  where transaction_type='earned' and expired_at is null;

alter table public.loyalty_program_settings enable row level security;
drop policy if exists loyalty_program_settings_admin_read on public.loyalty_program_settings;
create policy loyalty_program_settings_admin_read on public.loyalty_program_settings
for select to authenticated using ((select public.is_admin()));

grant select on public.loyalty_program_settings to authenticated;

create or replace function public.admin_update_loyalty_rules(
 p_is_enabled boolean, p_earn_amount_toman numeric, p_earn_points integer,
 p_point_value_toman numeric, p_minimum_redeem_points integer,
 p_maximum_discount_percent numeric, p_expiry_days integer
) returns void language plpgsql security invoker set search_path=''
as $$
begin
 if not (select public.is_admin()) then raise exception 'Administrator access required' using errcode='42501'; end if;
 if p_earn_amount_toman<=0 or p_earn_points<=0 or p_point_value_toman<=0
   or p_minimum_redeem_points<=0 or p_maximum_discount_percent not between 1 and 100
   or p_expiry_days not between 1 and 3650 then
   raise exception 'Invalid loyalty rules' using errcode='22023';
 end if;
 insert into public.loyalty_program_settings(id,is_enabled,earn_amount_toman,earn_points,
   point_value_toman,minimum_redeem_points,maximum_discount_percent,expiry_days,updated_at,updated_by)
 values(true,p_is_enabled,p_earn_amount_toman,p_earn_points,p_point_value_toman,
   p_minimum_redeem_points,p_maximum_discount_percent,p_expiry_days,now(),auth.uid())
 on conflict(id) do update set is_enabled=excluded.is_enabled,
   earn_amount_toman=excluded.earn_amount_toman,earn_points=excluded.earn_points,
   point_value_toman=excluded.point_value_toman,minimum_redeem_points=excluded.minimum_redeem_points,
   maximum_discount_percent=excluded.maximum_discount_percent,expiry_days=excluded.expiry_days,
   updated_at=now(),updated_by=auth.uid();
end; $$;
revoke all on function public.admin_update_loyalty_rules(boolean,numeric,integer,numeric,integer,numeric,integer) from public,anon;
grant execute on function public.admin_update_loyalty_rules(boolean,numeric,integer,numeric,integer,numeric,integer) to authenticated;

-- Expires only the still-unexpired earned transactions, subtracting points once
-- under a row lock. The ledger keeps an explicit negative expiry transaction.
create or replace function public.admin_expire_loyalty_points()
returns integer language plpgsql security invoker set search_path=''
as $$
declare r record; v_expired integer:=0; v_points integer;
begin
 if not (select public.is_admin()) then raise exception 'Administrator access required' using errcode='42501'; end if;
 for r in
   select t.id,t.wallet_id,t.points
   from public.loyalty_transactions t
   where t.transaction_type='earned' and t.expired_at is null
     and t.expires_at is not null and t.expires_at<=now()
   order by t.expires_at
   for update
 loop
   v_points:=greatest(r.points,0);
   if v_points>0 then
     update public.loyalty_wallets
       set total_points=greatest(0,total_points-v_points),updated_at=now()
       where id=r.wallet_id;
     insert into public.loyalty_transactions(wallet_id,order_id,points,transaction_type,description)
       values(r.wallet_id,null,-v_points,'expired','انقضای امتیازهای استفاده‌نشده');
     v_expired:=v_expired+v_points;
   end if;
   update public.loyalty_transactions set expired_at=now() where id=r.id;
 end loop;
 return v_expired;
end; $$;
revoke all on function public.admin_expire_loyalty_points() from public,anon;
grant execute on function public.admin_expire_loyalty_points() to authenticated;

-- Calculates a safe discount quote in toman; redemption itself must be performed
-- atomically at checkout by the customer application using this same rule set.
create or replace function public.admin_quote_loyalty_discount(p_user_id uuid,p_points integer,p_order_amount_toman numeric)
returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_balance integer; v_min integer; v_value numeric; v_cap numeric; v_discount numeric;
begin
 if not (select public.is_admin()) then raise exception 'Administrator access required' using errcode='42501'; end if;
 if p_user_id is null or p_points<=0 or p_order_amount_toman<=0 then raise exception 'Invalid discount request' using errcode='22023'; end if;
 select coalesce(w.total_points,0) into v_balance from public.loyalty_wallets w where w.user_identifier=p_user_id;
 select minimum_redeem_points,point_value_toman,maximum_discount_percent
 into v_min,v_value,v_cap from public.loyalty_program_settings where id=true and is_enabled;
 if not found then raise exception 'Loyalty program is disabled' using errcode='22023'; end if;
 if p_points<v_min or p_points>coalesce(v_balance,0) then raise exception 'Insufficient points or below minimum redemption' using errcode='22023'; end if;
 v_discount:=least(p_points*v_value,p_order_amount_toman*v_cap/100);
 return jsonb_build_object('points',p_points,'discount_toman',floor(v_discount),'balance',coalesce(v_balance,0));
end; $$;
revoke all on function public.admin_quote_loyalty_discount(uuid,integer,numeric) from public,anon;
grant execute on function public.admin_quote_loyalty_discount(uuid,integer,numeric) to authenticated;

commit;
