-- Customer order placement must use the validated public.place_order() RPC.
-- Direct table inserts are reserved for active CRM administrators.
DROP POLICY IF EXISTS orders_insert ON public.orders;
CREATE POLICY orders_insert_admin_only
  ON public.orders FOR INSERT TO authenticated
  WITH CHECK ((SELECT public.is_admin()));

DROP POLICY IF EXISTS order_items_insert ON public.order_items;
CREATE POLICY order_items_insert_admin_only
  ON public.order_items FOR INSERT TO authenticated
  WITH CHECK ((SELECT public.is_admin()));

REVOKE INSERT ON TABLE public.orders, public.order_items FROM anon, PUBLIC;
GRANT INSERT ON TABLE public.orders, public.order_items TO authenticated;
