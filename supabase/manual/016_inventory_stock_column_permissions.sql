-- Prevent direct client writes to quantity_on_hand. All balance changes must
-- pass through the stock receive/adjust/waste/return RPCs or the order trigger.
REVOKE INSERT, UPDATE, DELETE ON public.inventory_materials FROM authenticated;
GRANT SELECT ON public.inventory_materials TO authenticated;
GRANT INSERT (id,name,sku,unit,unit_cost,reorder_level,is_active,notes,updated_at)
  ON public.inventory_materials TO authenticated;
GRANT UPDATE (id,name,sku,unit,unit_cost,reorder_level,is_active,notes,updated_at)
  ON public.inventory_materials TO authenticated;
