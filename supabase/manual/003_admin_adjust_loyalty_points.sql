-- Atomic, admin-only points adjustment with an auditable ledger entry.
-- Run this migration before using the CRM loyalty adjustment action.

begin;

create or replace function public.admin_adjust_loyalty_points(
  p_user_id uuid,
  p_points integer,
  p_description text
)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_wallet_id uuid;
  v_current_points integer;
  v_new_points integer;
begin
  if not public.is_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;

  if p_user_id is null then
    raise exception 'Customer id is required' using errcode = '22023';
  end if;
  if p_points is null or p_points = 0 then
    raise exception 'Points delta must not be zero' using errcode = '22023';
  end if;
  if p_description is null or pg_catalog.length(pg_catalog.btrim(p_description)) = 0 then
    raise exception 'Adjustment reason is required' using errcode = '22023';
  end if;

  insert into public.loyalty_wallets (user_identifier, total_points)
  values (p_user_id, 0)
  on conflict (user_identifier) do nothing;

  select w.id, w.total_points
    into v_wallet_id, v_current_points
    from public.loyalty_wallets w
   where w.user_identifier = p_user_id
   for update;

  v_new_points := v_current_points + p_points;
  if v_new_points < 0 then
    raise exception 'Adjustment would make loyalty balance negative' using errcode = '22023';
  end if;

  update public.loyalty_wallets
     set total_points = v_new_points,
         updated_at = pg_catalog.now()
   where id = v_wallet_id;

  insert into public.loyalty_transactions (
    wallet_id, order_id, points, transaction_type, description
  ) values (
    v_wallet_id, null, p_points, 'adjusted', pg_catalog.btrim(p_description)
  );

  return v_new_points;
end;
$function$;

revoke all on function public.admin_adjust_loyalty_points(uuid, integer, text) from public;
revoke all on function public.admin_adjust_loyalty_points(uuid, integer, text) from anon;
grant execute on function public.admin_adjust_loyalty_points(uuid, integer, text) to authenticated;

commit;
