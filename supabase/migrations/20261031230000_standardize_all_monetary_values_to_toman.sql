-- Standardize monetary values to Iranian toman across the CRM and restaurant system.
-- Existing wallet rows were verified to use IRT; no numeric balances are converted.
alter table public.customer_wallets
  alter column currency set default 'IRT';

alter table public.customer_wallets
  drop constraint if exists customer_wallets_currency_check;

alter table public.customer_wallets
  add constraint customer_wallets_currency_check
  check (currency = 'IRT');

comment on column public.customer_wallets.balance is 'All monetary values are stored and displayed in Iranian toman (IRT).';
comment on column public.customer_wallets.currency is 'Fixed internal currency code IRT; user-facing unit is toman.';
comment on column public.customer_wallet_transactions.amount_delta is 'Transaction amount in Iranian toman.';
comment on column public.customer_wallet_transactions.balance_after is 'Wallet balance after transaction, in Iranian toman.';
comment on column public.orders.total_amount is 'Order total in Iranian toman.';
comment on column public.orders.subtotal_amount is 'Order subtotal in Iranian toman.';
comment on column public.orders.discount_amount is 'Discount amount in Iranian toman.';
comment on column public.orders.delivery_fee is 'Delivery fee in Iranian toman.';
comment on column public.order_items.unit_price is 'Item unit price in Iranian toman.';
comment on column public.products.price is 'Product price in Iranian toman.';
comment on column public.order_payments.amount is 'Received payment amount in Iranian toman.';
comment on column public.order_refunds.amount is 'Refund amount in Iranian toman.';
comment on column public.restaurant_expenses.amount is 'Expense amount in Iranian toman.';
comment on column public.inventory_purchases.total_amount is 'Inventory purchase total in Iranian toman.';
comment on column public.inventory_purchases.discount_amount is 'Inventory purchase discount in Iranian toman.';
