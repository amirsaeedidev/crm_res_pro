-- Enables the CRM to read profile+email data without granting direct access to
-- auth.users. The view is intentionally SECURITY DEFINER, but its predicate
-- exposes all users only to active admins; ordinary accounts see only their
-- own row, and anonymous requests see none.
-- Review and run in Supabase SQL Editor before using Customer/Ticket screens.

begin;

create or replace view public.users
with (security_invoker = false)
as
select
  p.id,
  coalesce(p.first_name, '')::text as first_name,
  coalesce(p.last_name, '')::text as last_name,
  u.email,
  p.phone,
  p.avatar_url,
  p.role,
  p.status,
  p.created_at
from public.profiles p
left join auth.users u on u.id = p.id
where public.is_admin() or p.id = (select auth.uid());

grant select on public.users to anon, authenticated;

commit;
