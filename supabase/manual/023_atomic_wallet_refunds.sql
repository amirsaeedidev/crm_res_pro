-- Wallet refunds: atomic balance update and idempotent transaction ledger.
create unique index if not exists customer_wallets_user_id_uidx on public.customer_wallets(user_id);

create or replace function public.process_order_refund_to_wallet(p_refund_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_refund public.order_refunds%rowtype;
  v_order public.orders%rowtype;
  v_wallet public.customer_wallets%rowtype;
  v_txn_id uuid;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Only administrators can process refunds' using errcode = '42501';
  end if;

  select * into v_refund from public.order_refunds where id = p_refund_id for update;
  if not found then raise exception 'Refund request not found'; end if;
  if v_refund.status = 'refunded' then
    return jsonb_build_object('success', true, 'already_processed', true, 'refund_id', p_refund_id);
  end if;
  if v_refund.status = 'rejected' then raise exception 'Rejected refund cannot be processed'; end if;
  if v_refund.refund_method <> 'wallet' then raise exception 'This request is not marked for wallet refund'; end if;

  select * into v_order from public.orders where id = v_refund.order_id for update;
  if not found then raise exception 'Order not found'; end if;
  if v_order.status <> 'cancelled' then raise exception 'Order must be cancelled before refunding'; end if;

  if exists (select 1 from public.customer_wallet_transactions where idempotency_key = 'order-refund:' || v_refund.id::text) then
    update public.order_refunds set status='refunded', processed_by=auth.uid(),
      processed_at=coalesce(processed_at, now()), updated_at=now() where id=v_refund.id;
    return jsonb_build_object('success', true, 'already_processed', true, 'refund_id', p_refund_id);
  end if;

  insert into public.customer_wallets(user_id, balance, currency) values (v_order.user_id, 0, 'IRT')
    on conflict (user_id) do nothing;
  select * into v_wallet from public.customer_wallets where user_id=v_order.user_id for update;
  update public.customer_wallets set balance=balance + v_refund.amount, updated_at=now()
    where id=v_wallet.id returning * into v_wallet;

  insert into public.customer_wallet_transactions(wallet_id,user_id,amount_delta,balance_after,transaction_type,reason,order_id,performed_by,idempotency_key)
  values (v_wallet.id,v_order.user_id,v_refund.amount,v_wallet.balance,'refund',
    'بازپرداخت سفارش لغوشده: ' || v_refund.reason,v_order.id,auth.uid(),'order-refund:' || v_refund.id::text)
  returning id into v_txn_id;

  update public.order_refunds set status='refunded', processed_by=auth.uid(), processed_at=now(),
    updated_at=now(), reference_number=coalesce(reference_number,v_txn_id::text) where id=v_refund.id;

  return jsonb_build_object('success',true,'refund_id',p_refund_id,'wallet_id',v_wallet.id,
    'transaction_id',v_txn_id,'amount',v_refund.amount,'balance_after',v_wallet.balance);
end;
$$;
revoke all on function public.process_order_refund_to_wallet(uuid) from public;
grant execute on function public.process_order_refund_to_wallet(uuid) to authenticated;
