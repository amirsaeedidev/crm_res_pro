-- Harden monetary wallet and inventory ledgers; add explicit waste/return movements.
-- Safe to re-run.

DROP POLICY IF EXISTS customer_wallets_select_own ON public.customer_wallets;
CREATE POLICY customer_wallets_select_own ON public.customer_wallets
  FOR SELECT TO authenticated USING ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS customer_wallet_transactions_select_own ON public.customer_wallet_transactions;
CREATE POLICY customer_wallet_transactions_select_own ON public.customer_wallet_transactions
  FOR SELECT TO authenticated USING ((SELECT auth.uid()) = user_id);

-- These are append-only ledgers. Mutations must pass through guarded RPCs/triggers.
REVOKE INSERT, UPDATE, DELETE ON public.customer_wallets FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.customer_wallet_transactions FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.inventory_transactions FROM authenticated;
GRANT SELECT ON public.customer_wallets, public.customer_wallet_transactions,
  public.inventory_transactions TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_record_inventory_movement(
  p_material_id uuid,
  p_quantity numeric,
  p_transaction_type text,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_material public.inventory_materials%rowtype;
  v_delta numeric(14,3);
  v_balance numeric(14,3);
  v_reason text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Administrator access required' USING ERRCODE='42501';
  END IF;
  IF p_material_id IS NULL OR p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than zero' USING ERRCODE='22023';
  END IF;
  IF p_transaction_type NOT IN ('waste','return') THEN
    RAISE EXCEPTION 'Movement type must be waste or return' USING ERRCODE='22023';
  END IF;
  v_reason := pg_catalog.btrim(coalesce(p_reason,''));
  IF v_reason = '' THEN
    RAISE EXCEPTION 'Reason is required' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_material
    FROM public.inventory_materials
   WHERE id=p_material_id AND is_active=true
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Material not found or inactive' USING ERRCODE='P0002';
  END IF;
  v_delta := CASE WHEN p_transaction_type='waste' THEN -p_quantity ELSE p_quantity END;
  v_balance := v_material.quantity_on_hand + v_delta;
  IF v_balance < 0 THEN
    RAISE EXCEPTION 'Insufficient stock for waste movement' USING ERRCODE='22023';
  END IF;
  IF v_balance > 1000000000 THEN
    RAISE EXCEPTION 'Stock quantity is out of range' USING ERRCODE='22023';
  END IF;
  UPDATE public.inventory_materials
     SET quantity_on_hand=v_balance, updated_at=pg_catalog.now()
   WHERE id=p_material_id;
  INSERT INTO public.inventory_transactions(
    material_id, transaction_type, quantity_delta, unit_cost, total_cost, reason, performed_by
  ) VALUES (
    p_material_id, p_transaction_type, v_delta, v_material.unit_cost,
    round(p_quantity*v_material.unit_cost,2), v_reason, (SELECT auth.uid())
  );
  RETURN pg_catalog.jsonb_build_object(
    'material_id',p_material_id,'quantity_on_hand',v_balance,'transaction_type',p_transaction_type
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_record_inventory_movement(uuid,numeric,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admin_record_inventory_movement(uuid,numeric,text,text) TO authenticated;
