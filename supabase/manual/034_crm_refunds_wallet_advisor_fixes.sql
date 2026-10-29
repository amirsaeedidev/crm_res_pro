-- Resolve CRM refund lookup indexes/RLS initplan and remove a proven duplicate wallet index.
begin;

create index if not exists order_refunds_requested_by_idx
  on public.order_refunds(requested_by) where requested_by is not null;
create index if not exists order_refunds_processed_by_idx
  on public.order_refunds(processed_by) where processed_by is not null;

drop policy if exists order_refunds_admin_select on public.order_refunds;
create policy order_refunds_admin_select on public.order_refunds
for select to authenticated
using ((select public.is_admin()));

drop policy if exists order_refunds_admin_insert on public.order_refunds;
create policy order_refunds_admin_insert on public.order_refunds
for insert to authenticated
with check ((select public.is_admin()) and requested_by = (select auth.uid()));

drop policy if exists order_refunds_admin_update on public.order_refunds;
create policy order_refunds_admin_update on public.order_refunds
for update to authenticated
using ((select public.is_admin()))
with check ((select public.is_admin()));

-- customer_wallets_user_id_key is backed by the unique constraint; the plain duplicate
-- index customer_wallets_user_id_uidx has the same key and adds unnecessary write cost.
drop index if exists public.customer_wallets_user_id_uidx;

commit;
