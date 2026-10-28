-- Receipt logo storage bucket and admin-only mutations.
-- Run in Supabase SQL Editor after deploying the CRM code.

begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'receipt-logos',
  'receipt-logos',
  true,
  2097152,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Receipt logos are publicly readable" on storage.objects;
create policy "Receipt logos are publicly readable"
on storage.objects for select
to anon, authenticated
using (bucket_id = 'receipt-logos');

drop policy if exists "Admins upload receipt logos" on storage.objects;
create policy "Admins upload receipt logos"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'receipt-logos'
  and (select public.is_admin())
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "Admins update receipt logos" on storage.objects;
create policy "Admins update receipt logos"
on storage.objects for update
to authenticated
using (
  bucket_id = 'receipt-logos'
  and (select public.is_admin())
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'receipt-logos'
  and (select public.is_admin())
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "Admins delete receipt logos" on storage.objects;
create policy "Admins delete receipt logos"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'receipt-logos'
  and (select public.is_admin())
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

commit;
