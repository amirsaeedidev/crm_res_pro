-- Applied to the connected Supabase project.
-- Private Excel archive and per-import results for inventory management.
begin;
create table if not exists public.inventory_import_batches (
  id uuid primary key default gen_random_uuid(),
  file_name text not null,
  storage_path text not null,
  import_type text not null check (import_type in ('materials','recipes')),
  status text not null default 'completed' check (status in ('completed','partial','failed')),
  rows_total integer not null default 0 check (rows_total >= 0),
  rows_success integer not null default 0 check (rows_success >= 0),
  rows_failed integer not null default 0 check (rows_failed >= 0),
  error_summary text not null default '',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists inventory_import_batches_created_idx on public.inventory_import_batches(created_at desc);
alter table public.inventory_import_batches enable row level security;
drop policy if exists inventory_import_batches_admin_all on public.inventory_import_batches;
create policy inventory_import_batches_admin_all on public.inventory_import_batches
for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
grant select, insert, update, delete on public.inventory_import_batches to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('inventory-imports','inventory-imports',false,15728640,
  array['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/vnd.ms-excel','text/csv'])
on conflict (id) do update set public=false,file_size_limit=15728640,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists inventory_imports_admin_select on storage.objects;
create policy inventory_imports_admin_select on storage.objects for select to authenticated
using (bucket_id='inventory-imports' and (select public.is_admin()));
drop policy if exists inventory_imports_admin_insert on storage.objects;
create policy inventory_imports_admin_insert on storage.objects for insert to authenticated
with check (bucket_id='inventory-imports' and (select public.is_admin()));
drop policy if exists inventory_imports_admin_delete on storage.objects;
create policy inventory_imports_admin_delete on storage.objects for delete to authenticated
using (bucket_id='inventory-imports' and (select public.is_admin()));
commit;