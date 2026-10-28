-- Cover frequently joined/referenced foreign keys for wallet and inventory ledgers.
CREATE INDEX IF NOT EXISTS customer_wallet_transactions_order_idx ON public.customer_wallet_transactions(order_id) WHERE order_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS customer_wallet_transactions_performed_by_idx ON public.customer_wallet_transactions(performed_by) WHERE performed_by IS NOT NULL;
CREATE INDEX IF NOT EXISTS inventory_transactions_performed_by_idx ON public.inventory_transactions(performed_by) WHERE performed_by IS NOT NULL;
CREATE INDEX IF NOT EXISTS receipt_settings_updated_by_idx ON public.receipt_settings(updated_by) WHERE updated_by IS NOT NULL;
