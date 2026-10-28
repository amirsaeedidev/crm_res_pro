-- Admin CRUD table grants aligned with existing RLS policies.
-- RLS remains enabled; these are table privileges, not row-level authorization.
-- Idempotent and safe to re-run in this project's schema.

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.addresses TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE public.discounts TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE public.products TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.loyalty_transactions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.loyalty_wallets TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.order_items TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.reservations TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.inventory_materials TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.inventory_transactions TO authenticated;
GRANT UPDATE, DELETE ON TABLE public.tickets TO authenticated;
GRANT UPDATE, DELETE ON TABLE public.ticket_messages TO authenticated;
GRANT DELETE ON TABLE public.sms_settings TO authenticated;

-- These indexes were confirmed identical and not constraint-backed.
DROP INDEX IF EXISTS public.idx_customer_notifications_user_created;
DROP INDEX IF EXISTS public.idx_customer_notifications_unread;
