-- Applied Supabase migrations for product images and whole-toman money contract.
-- Project: cfdzxtnkiptnlitwvnla
--
-- Product Storage bucket is public-read for catalog images and admin-write only
-- (policies are maintained in the shared Supabase project).
update storage.buckets
set file_size_limit = 12582912,
    allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif','image/avif']::text[]
where id = 'products';

-- Currency unit is Iranian toman. Product base price is INTEGER already.
comment on column public.products.price is 'Product base price in Iranian toman (whole integer).';
comment on column public.products.discounted_price is 'Generated discounted product price in Iranian toman, rounded to a whole toman.';
comment on column public.order_items.unit_price is 'Order item unit price in Iranian toman.';
comment on column public.order_items.total_price is 'Order item total price in Iranian toman.';
comment on column public.orders.subtotal_amount is 'Order subtotal in Iranian toman.';
comment on column public.orders.discount_amount is 'Order discount amount in Iranian toman.';
comment on column public.orders.delivery_fee is 'Delivery fee in Iranian toman.';
comment on column public.orders.total_amount is 'Order total in Iranian toman.';
comment on column public.order_payments.amount is 'Received payment amount in Iranian toman.';
comment on column public.order_refunds.amount is 'Refund amount in Iranian toman.';
comment on column public.restaurant_expenses.amount is 'Expense amount in Iranian toman.';
comment on column public.discounts.discount_value is 'Discount value: percent points for percent discounts; Iranian toman for fixed discounts.';
comment on column public.discounts.min_order_amount is 'Minimum qualifying order amount in Iranian toman.';
comment on column public.discounts.max_discount_amount is 'Maximum discount cap in Iranian toman.';
comment on column public.restaurant_settings.min_delivery_amount is 'Minimum delivery order amount in Iranian toman.';

-- Whole-toman constraints. Preflight confirmed no existing fractional rows.
alter table public.products add constraint products_discounted_price_whole_toman
  check (discounted_price is null or discounted_price = trunc(discounted_price)) not valid;
alter table public.products validate constraint products_discounted_price_whole_toman;
alter table public.orders add constraint orders_amounts_whole_toman
  check (total_amount = trunc(total_amount) and subtotal_amount = trunc(subtotal_amount)
    and discount_amount = trunc(discount_amount) and delivery_fee = trunc(delivery_fee)) not valid;
alter table public.orders validate constraint orders_amounts_whole_toman;
alter table public.order_items add constraint order_items_amounts_whole_toman
  check (unit_price = trunc(unit_price) and total_price = trunc(total_price)) not valid;
alter table public.order_items validate constraint order_items_amounts_whole_toman;
alter table public.order_payments add constraint order_payments_amount_whole_toman
  check (amount = trunc(amount)) not valid;
alter table public.order_payments validate constraint order_payments_amount_whole_toman;
alter table public.order_refunds add constraint order_refunds_amount_whole_toman
  check (amount = trunc(amount)) not valid;
alter table public.order_refunds validate constraint order_refunds_amount_whole_toman;
alter table public.restaurant_expenses add constraint restaurant_expenses_amount_whole_toman
  check (amount = trunc(amount)) not valid;
alter table public.restaurant_expenses validate constraint restaurant_expenses_amount_whole_toman;
alter table public.inventory_purchases add constraint inventory_purchases_amounts_whole_toman
  check (total_amount = trunc(total_amount) and discount_amount = trunc(discount_amount)) not valid;
alter table public.inventory_purchases validate constraint inventory_purchases_amounts_whole_toman;
