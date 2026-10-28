-- Enables Realtime event delivery for the events consumed by NotificationsProvider.
-- Run after checking the publication name and existing table membership.

begin;

do $block$
begin
  if not exists (
    select 1 from pg_catalog.pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'orders'
  ) then
    execute 'alter publication supabase_realtime add table public.orders';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'reservations'
  ) then
    execute 'alter publication supabase_realtime add table public.reservations';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'profiles'
  ) then
    execute 'alter publication supabase_realtime add table public.profiles';
  end if;
end;
$block$;

commit;
