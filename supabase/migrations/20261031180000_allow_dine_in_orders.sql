-- The original address constraint unintentionally excluded dine-in orders.
alter table public.orders
  drop constraint if exists delivery_requires_address;
alter table public.orders
  add constraint delivery_requires_address
  check (
    (order_type = 'delivery' and address_id is not null)
    or order_type in ('pickup', 'dine_in')
  );
