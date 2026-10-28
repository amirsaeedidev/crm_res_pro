-- Use a sargable UTC timestamp range while assigning the daily queue number
-- using the restaurant's Asia/Baku local day.
CREATE OR REPLACE FUNCTION public.assign_daily_queue_number()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_date date;
  v_start timestamptz;
  v_end timestamptz;
BEGIN
  IF NEW.created_at IS NULL THEN
    NEW.created_at := pg_catalog.now();
  END IF;
  v_date := (NEW.created_at AT TIME ZONE 'Asia/Baku')::date;
  v_start := v_date::timestamp AT TIME ZONE 'Asia/Baku';
  v_end := (v_date + 1)::timestamp AT TIME ZONE 'Asia/Baku';

  IF NEW.daily_queue_number IS NULL THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('daily-queue-baku-' || v_date::text)
    );
    SELECT COALESCE(MAX(o.daily_queue_number), 0) + 1
      INTO NEW.daily_queue_number
      FROM public.orders o
     WHERE o.created_at >= v_start
       AND o.created_at < v_end;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.assign_daily_queue_number()
  FROM PUBLIC, anon, authenticated;

UPDATE public.customer_wallets
   SET currency = 'IRT'
 WHERE currency IS DISTINCT FROM 'IRT';
