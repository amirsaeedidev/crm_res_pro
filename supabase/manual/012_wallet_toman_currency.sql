-- The CRM labels customer wallet amounts as Toman.
ALTER TABLE public.customer_wallets ALTER COLUMN currency SET DEFAULT 'IRT';
UPDATE public.customer_wallets SET currency='IRT' WHERE currency='IRR' AND balance=0;
