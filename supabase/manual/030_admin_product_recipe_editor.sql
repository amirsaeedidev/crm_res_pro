-- Atomic replacement of a product's ingredient recipe from the CRM.
create or replace function public.admin_set_product_recipe(p_product_id uuid,p_items jsonb)
returns void language plpgsql security invoker set search_path='' as $$
declare v_item jsonb; v_material_id uuid; v_qty numeric; v_seen uuid[] := '{}';
begin
 if not (select public.is_admin()) then raise exception 'Administrator access required' using errcode='42501'; end if;
 if not exists(select 1 from public.products where id=p_product_id) then raise exception 'Product not found' using errcode='22023'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Recipe must be an array' using errcode='22023'; end if;
 for v_item in select value from jsonb_array_elements(p_items) loop
   v_material_id:=(v_item->>'material_id')::uuid;
   v_qty:=(v_item->>'quantity_per_product')::numeric;
   if v_qty is null or v_qty<=0 then raise exception 'Ingredient quantity must be greater than zero' using errcode='22023'; end if;
   if v_material_id=any(v_seen) then raise exception 'Duplicate ingredient in recipe' using errcode='22023'; end if;
   if not exists(select 1 from public.inventory_materials where id=v_material_id and is_active=true) then raise exception 'Ingredient not found or inactive' using errcode='22023'; end if;
   v_seen:=array_append(v_seen,v_material_id);
 end loop;
 delete from public.product_recipes where product_id=p_product_id;
 for v_item in select value from jsonb_array_elements(p_items) loop
   insert into public.product_recipes(product_id,material_id,quantity_per_product,notes)
   values(p_product_id,(v_item->>'material_id')::uuid,(v_item->>'quantity_per_product')::numeric,coalesce(v_item->>'notes',''));
 end loop;
end; $$;
revoke all on function public.admin_set_product_recipe(uuid,jsonb) from public,anon;
grant execute on function public.admin_set_product_recipe(uuid,jsonb) to authenticated;
