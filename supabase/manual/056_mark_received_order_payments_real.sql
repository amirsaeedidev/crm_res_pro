-- A received payment ledger entry is the trusted signal that an order
-- has moved from the simulated checkout mode to a real/manual received payment.
CREATE OR REPLACE FUNCTION public.mark_order_payment_mode_real()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NEW.status = 'received' THEN
    UPDATE public.orders
       SET payment_mode = 'real'
     WHERE id = NEW.order_id
       AND payment_mode IS DISTINCT FROM 'real';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.mark_order_payment_mode_real() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS order_payments_mark_real_mode ON public.order_payments;
CREATE TRIGGER order_payments_mark_real_mode
AFTER INSERT OR UPDATE OF status, order_id
ON public.order_payments
FOR EACH ROW
EXECUTE FUNCTION public.mark_order_payment_mode_real();
