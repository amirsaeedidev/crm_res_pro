-- Expose receipt/order-number fields to the admin order list and details API.
-- Existing order view columns remain in their original order; new columns append at the end.
CREATE OR REPLACE VIEW public.orders_view WITH (security_invoker = true) AS
SELECT
  o.id,
  o.user_id,
  (COALESCE(p.first_name, ''::text) || ' '::text) || COALESCE(p.last_name, ''::text) AS customer_name,
  COALESCE(p.phone, ''::text) AS customer_phone,
  o.address_id,
  o.order_type,
  o.status,
  o.total_amount,
  o.estimated_ready_minutes,
  o.admin_note,
  o.completed_at,
  o.created_at,
  o.updated_at,
  o.assigned_staff_id,
  o.subtotal_amount,
  o.discount_amount,
  o.discount_code,
  o.table_number,
  o.daily_queue_number
FROM public.orders o
LEFT JOIN public.profiles p ON p.id = o.user_id;
GRANT SELECT ON public.orders_view TO authenticated;
