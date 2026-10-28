-- Supabase Realtime subscriptions used by the CRM wallet and stock screens.
DO $$
DECLARE
  t text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname='supabase_realtime') THEN
    RAISE NOTICE 'supabase_realtime publication not found; skipping';
    RETURN;
  END IF;
  FOREACH t IN ARRAY ARRAY[
    'customer_wallets',
    'customer_wallet_transactions',
    'inventory_materials',
    'product_recipes',
    'inventory_transactions'
  ] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
       WHERE pubname='supabase_realtime'
         AND schemaname='public'
         AND tablename=t
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    END IF;
  END LOOP;
END $$;
