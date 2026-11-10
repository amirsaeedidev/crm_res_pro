-- Enforce per-customer coupon limits against the canonical redemption ledger.
-- Orders are mutable business records; discount_redemptions is the immutable,
-- discount-id-based source of truth (released rows do not consume capacity).
begin;

do $migration$
declare
  v_definition text;
  v_updated text;
begin
  select pg_catalog.pg_get_functiondef('public.quote_discount_code(text,jsonb)'::regprocedure)
    into v_definition;
  v_updated := replace(
    v_definition,
    $old$select count(*) from public.orders o
    where o.user_id=v_user_id and pg_catalog.upper(coalesce(o.discount_code,''))=pg_catalog.upper(v_discount.code)
      and o.status <> 'cancelled'$old$,
    $new$select count(*) from public.discount_redemptions r
    where r.discount_id=v_discount.id and r.user_id=v_user_id and r.status='redeemed'$new$
  );
  if v_updated = v_definition then
    raise exception 'Could not locate per-customer usage check in quote_discount_code';
  end if;
  execute v_updated;

  select pg_catalog.pg_get_functiondef(
    'public.place_order_idempotent(uuid,text,jsonb,uuid,text,integer,uuid,text,text)'::regprocedure
  ) into v_definition;
  v_updated := replace(
    v_definition,
    $old$(select count(*) from public.orders o where o.user_id=v_user_id and pg_catalog.upper(coalesce(o.discount_code,''))=pg_catalog.upper(v_discount_row.code) and o.status<>'cancelled')$old$,
    $new$(select count(*) from public.discount_redemptions r where r.discount_id=v_discount_row.id and r.user_id=v_user_id and r.status='redeemed')$new$
  );
  if v_updated = v_definition then
    raise exception 'Could not locate per-customer usage check in place_order_idempotent';
  end if;
  execute v_updated;

  select pg_catalog.pg_get_functiondef('public.list_customer_discounts()'::regprocedure)
    into v_definition;
  v_updated := replace(
    v_definition,
    $old$select count(*) from public.orders o
        where o.user_id=auth.uid()
          and pg_catalog.upper(coalesce(o.discount_code,''))=pg_catalog.upper(d.code)
          and o.status <> 'cancelled'$old$,
    $new$select count(*) from public.discount_redemptions r
      where r.discount_id=d.id and r.user_id=auth.uid() and r.status='redeemed'$new$
  );
  if v_updated = v_definition then
    raise exception 'Could not locate per-customer usage check in list_customer_discounts';
  end if;
  execute v_updated;
end;
$migration$;

commit;
