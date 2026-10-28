-- Merge administrator/owner read rules to remove duplicate permissive SELECT policies.
-- This complements 013 and is safe to re-run.
DROP POLICY IF EXISTS customer_wallets_admin_all ON public.customer_wallets;
DROP POLICY IF EXISTS customer_wallets_select_own ON public.customer_wallets;
CREATE POLICY customer_wallets_admin_or_owner_select
ON public.customer_wallets FOR SELECT TO authenticated
USING ((SELECT public.is_admin()) OR (SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS customer_wallet_transactions_admin_all ON public.customer_wallet_transactions;
DROP POLICY IF EXISTS customer_wallet_transactions_select_own ON public.customer_wallet_transactions;
CREATE POLICY customer_wallet_transactions_admin_or_owner_select
ON public.customer_wallet_transactions FOR SELECT TO authenticated
USING ((SELECT public.is_admin()) OR (SELECT auth.uid()) = user_id);

REVOKE INSERT, UPDATE, DELETE ON public.customer_wallets FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.customer_wallet_transactions FROM authenticated;
GRANT SELECT ON public.customer_wallets, public.customer_wallet_transactions TO authenticated;
