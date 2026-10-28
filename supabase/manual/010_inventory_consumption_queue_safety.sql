-- The queue counter uses the restaurant's Asia/Baku calendar day.
-- Recipe deductions are idempotent, so cycling the status does not consume stock twice.
CREATE UNIQUE INDEX IF NOT EXISTS inventory_order_usage_once_idx
ON public.inventory_transactions(order_id, material_id)
WHERE transaction_type='order_usage' AND order_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.assign_daily_queue_number()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_date date;
BEGIN
 IF NEW.created_at IS NULL THEN NEW.created_at:=pg_catalog.now(); END IF;
 v_date:=(NEW.created_at AT TIME ZONE 'Asia/Baku')::date;
 IF NEW.daily_queue_number IS NULL THEN
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('daily-queue-baku-'||v_date::text));
  SELECT COALESCE(MAX(o.daily_queue_number),0)+1 INTO NEW.daily_queue_number
  FROM public.orders o WHERE (o.created_at AT TIME ZONE 'Asia/Baku')::date=v_date;
 END IF;
 RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.assign_daily_queue_number() FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.consume_order_recipe_inventory()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_recipe record; v_stock numeric(14,3); v_cost numeric(14,2);
BEGIN
 IF NEW.status='preparing' AND OLD.status IS DISTINCT FROM NEW.status THEN
  FOR v_recipe IN
   SELECT r.material_id, SUM(r.quantity_per_product*oi.quantity)::numeric(14,3) AS use_quantity
   FROM public.order_items oi JOIN public.product_recipes r ON r.product_id=oi.product_id
   WHERE oi.order_id=NEW.id GROUP BY r.material_id ORDER BY r.material_id
  LOOP
   IF EXISTS (SELECT 1 FROM public.inventory_transactions tx WHERE tx.order_id=NEW.id AND tx.material_id=v_recipe.material_id AND tx.transaction_type='order_usage') THEN CONTINUE; END IF;
   SELECT quantity_on_hand,unit_cost INTO v_stock,v_cost FROM public.inventory_materials
   WHERE id=v_recipe.material_id AND is_active=true FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'Recipe material % does not exist or is inactive',v_recipe.material_id USING ERRCODE='22023'; END IF;
   IF v_stock<v_recipe.use_quantity THEN RAISE EXCEPTION 'Insufficient stock for material %. Available %, required %',v_recipe.material_id,v_stock,v_recipe.use_quantity USING ERRCODE='22023'; END IF;
   UPDATE public.inventory_materials SET quantity_on_hand=quantity_on_hand-v_recipe.use_quantity,updated_at=pg_catalog.now() WHERE id=v_recipe.material_id;
   INSERT INTO public.inventory_transactions(material_id,transaction_type,quantity_delta,unit_cost,total_cost,order_id,reason)
   VALUES(v_recipe.material_id,'order_usage',-v_recipe.use_quantity,v_cost,round(v_recipe.use_quantity*v_cost,2),NEW.id,
          'مصرف مواد اولیه سفارش #'||COALESCE(NEW.daily_queue_number::text,LEFT(NEW.id::text,8)));
  END LOOP;
 END IF;
 RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.consume_order_recipe_inventory() FROM PUBLIC,anon,authenticated;
