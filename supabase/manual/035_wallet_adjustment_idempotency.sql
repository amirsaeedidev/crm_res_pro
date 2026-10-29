-- Make admin wallet balance adjustments idempotent.
-- A client must reuse the same key when retrying a request whose response may have been lost.
begin;

drop function if exists public.admin_adjust_customer_wallet(uuid, numeric, text, text);

create function public.admin_adjust_customer_wallet(
  p_user_id uuid,
  p_amount_delta numeric,
  p_reason text,
  p_transaction_type text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_wallet public.customer_wallets%rowtype;
  v_existing public.customer_wallet_transactions%rowtype;
  v_new_balance numeric(14,2);
  v_type text;
  v_reason text;
  v_key text;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if p_user_id is null then
    raise exception 'Customer id is required' using errcode = '22023';
  end if;
  if p_amount_delta is null or p_amount_delta = 0 or abs(p_amount_delta) > 100000000000 then
    raise exception 'Amount is zero or outside the allowed range' using errcode = '22023';
  end if;

  v_reason := pg_catalog.btrim(coalesce(p_reason, ''));
  if v_reason = '' then
    raise exception 'Reason is required' using errcode = '22023';
  end if;

  v_type := coalesce(nullif(pg_catalog.btrim(p_transaction_type), ''), 'adjustment');
  if v_type not in ('top_up', 'adjustment') then
    raise exception 'Unsupported wallet transaction type' using errcode = '22023';
  end if;
  if v_type = 'top_up' and p_amount_delta < 0 then
    raise exception 'Top-up amount must be positive' using errcode = '22023';
  end if;

  if p_idempotency_key is null or
     pg_catalog.length(pg_catalog.btrim(p_idempotency_key)) < 16 or
     pg_catalog.length(pg_catalog.btrim(p_idempotency_key)) > 128 then
    raise exception 'A valid idempotency key is required' using errcode = '22023';
  end if;
  v_key := 'admin-wallet-adjust:' || pg_catalog.btrim(p_idempotency_key);

  -- Serializes concurrent retries carrying the same key before checking the ledger.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(v_key));

  select * into v_existing
    from public.customer_wallet_transactions
   where idempotency_key = v_key;

  if found then
    if v_existing.user_id is distinct from p_user_id
       or v_existing.amount_delta is distinct from p_amount_delta
       or v_existing.transaction_type is distinct from v_type
       or v_existing.reason is distinct from v_reason
       or v_existing.performed_by is distinct from auth.uid() then
      raise exception 'Idempotency key has already been used for a different transaction'
        using errcode = '22023';
    end if;

    select * into v_wallet
      from public.customer_wallets
     where user_id = p_user_id
     for update;
    if not found then
      raise exception 'Wallet not found for an existing transaction' using errcode = 'P0002';
    end if;

    return pg_catalog.jsonb_build_object(
      'wallet_id', v_wallet.id,
      'user_id', p_user_id,
      'balance', v_wallet.balance,
      'transaction_id', v_existing.id,
      'already_processed', true
    );
  end if;

  insert into public.customer_wallets(user_id, balance, currency)
  values (p_user_id, 0, 'IRT')
  on conflict (user_id) do nothing;

  select * into v_wallet
    from public.customer_wallets
   where user_id = p_user_id
   for update;

  v_new_balance := v_wallet.balance + p_amount_delta;
  if v_new_balance < 0 then
    raise exception 'Wallet balance cannot be negative' using errcode = '22023';
  end if;

  update public.customer_wallets
     set balance = v_new_balance,
         currency = 'IRT',
         updated_at = pg_catalog.now()
   where id = v_wallet.id;

  insert into public.customer_wallet_transactions(
    wallet_id, user_id, amount_delta, balance_after, transaction_type, reason,
    performed_by, idempotency_key
  ) values (
    v_wallet.id, p_user_id, p_amount_delta, v_new_balance, v_type, v_reason,
    auth.uid(), v_key
  ) returning * into v_existing;

  return pg_catalog.jsonb_build_object(
    'wallet_id', v_wallet.id,
    'user_id', p_user_id,
    'balance', v_new_balance,
    'transaction_id', v_existing.id,
    'already_processed', false
  );
end;
$$;

revoke all on function public.admin_adjust_customer_wallet(uuid, numeric, text, text, text) from public, anon;
grant execute on function public.admin_adjust_customer_wallet(uuid, numeric, text, text, text) to authenticated;

commit;
