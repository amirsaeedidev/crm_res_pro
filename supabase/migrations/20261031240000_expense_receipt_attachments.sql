alter table public.restaurant_expenses
  add column if not exists receipt_path text;

comment on column public.restaurant_expenses.receipt_path is
  'Private Storage object path for the expense receipt; never store a public URL.';

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('expense-receipts', 'expense-receipts', false, 10485760,
        array['application/pdf','image/jpeg','image/png','image/webp'])
on conflict (id) do update
set public = false,
    file_size_limit = 10485760,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists expense_receipts_admin_select on storage.objects;
create policy expense_receipts_admin_select
on storage.objects for select to authenticated
using (bucket_id = 'expense-receipts' and (select public.is_admin()));

drop policy if exists expense_receipts_admin_insert on storage.objects;
create policy expense_receipts_admin_insert
on storage.objects for insert to authenticated
with check (bucket_id = 'expense-receipts' and (select public.is_admin()));

drop policy if exists expense_receipts_admin_delete on storage.objects;
create policy expense_receipts_admin_delete
on storage.objects for delete to authenticated
using (bucket_id = 'expense-receipts' and (select public.is_admin()));

grant select, insert, update, delete on public.restaurant_expenses to authenticated;
revoke all on public.restaurant_expenses from anon, public;
