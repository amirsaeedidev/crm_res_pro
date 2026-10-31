-- Admin notification events are inserted by table triggers. The trigger
-- function must retain SECURITY DEFINER so customer-side inserts can create
-- admin inbox rows despite the admin-only RLS policy, but it must never be
-- callable as a public RPC endpoint.
revoke execute on function public.create_admin_notification_for_row()
  from public, anon, authenticated;
