-- Persistent admin notifications for low stock and failed payment attempts.
-- The low-stock trigger only fires when stock first crosses the configured threshold.
-- Payment failures are logged only by authenticated active admins after a failed payment action.

create or replace function public.notify_admin_low_stock()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.is_active is distinct from true then
    return new;
  end if;

  if new.quantity_on_hand <= new.reorder_level
     and (
       tg_op = 'INSERT'
       or old.is_active is distinct from true
       or old.quantity_on_hand > old.reorder_level
     ) then
    insert into public.admin_notifications
      (title, body, notification_type, entity_table, entity_id)
    values (
      'هشدار کمبود موجودی انبار',
      'موجودی «' || new.name || '» به ' ||
        pg_catalog.trim_scale(new.quantity_on_hand)::text || ' ' || new.unit ||
        ' رسیده؛ حد هشدار: ' ||
        pg_catalog.trim_scale(new.reorder_level)::text || ' ' || new.unit || '.',
      'low_stock',
      'inventory_materials',
      new.id
    );
  end if;
  return new;
end;
$$;

revoke all on function public.notify_admin_low_stock() from public, anon, authenticated;
drop trigger if exists inventory_materials_notify_low_stock on public.inventory_materials;
create trigger inventory_materials_notify_low_stock
after insert or update of quantity_on_hand, reorder_level, is_active
on public.inventory_materials
for each row execute function public.notify_admin_low_stock();

create or replace function public.log_admin_payment_failure(
  p_order_id uuid,
  p_reason text default 'پرداخت ناموفق بود'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.orders%rowtype;
  v_notification_id uuid;
  v_reason text;
begin
  if auth.uid() is null or not coalesce(public.is_admin(), false) then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if p_order_id is null then
    raise exception 'Order id is required' using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id;
  if not found then
    raise exception 'Order not found' using errcode = 'P0002';
  end if;

  v_reason := nullif(pg_catalog.left(pg_catalog.btrim(coalesce(p_reason, '')), 240), '');
  if v_reason is null then
    v_reason := 'پرداخت ناموفق بود';
  end if;

  insert into public.admin_notifications
    (title, body, notification_type, entity_table, entity_id)
  values (
    'خطای پرداخت سفارش',
    'پرداخت سفارش #' ||
      coalesce(v_order.daily_queue_number::text, pg_catalog.left(v_order.id::text, 8)) ||
      ' ناموفق بود. علت: ' || v_reason,
    'payment_failed',
    'orders',
    v_order.id
  )
  returning id into v_notification_id;

  return v_notification_id;
end;
$$;

revoke all on function public.log_admin_payment_failure(uuid,text) from public, anon;
grant execute on function public.log_admin_payment_failure(uuid,text) to authenticated;
