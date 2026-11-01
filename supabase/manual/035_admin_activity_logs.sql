-- Admin activity audit trail.
-- Run this migration in the Supabase SQL Editor before opening /activity-logs.
create table if not exists public.admin_activity_logs (
  id bigint generated always as identity primary key,
  table_name text not null,
  record_id text,
  operation text not null check (operation in ('INSERT', 'UPDATE', 'DELETE')),
  actor_id uuid,
  created_at timestamptz not null default now()
);

create index if not exists admin_activity_logs_created_at_idx
  on public.admin_activity_logs (created_at desc);
create index if not exists admin_activity_logs_table_name_idx
  on public.admin_activity_logs (table_name, created_at desc);

alter table public.admin_activity_logs enable row level security;

drop policy if exists "Active admins can read activity logs" on public.admin_activity_logs;
create policy "Active admins can read activity logs"
  on public.admin_activity_logs
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.role = 'admin'
        and p.status = 'active'
    )
  );

revoke all on public.admin_activity_logs from anon;
grant select on public.admin_activity_logs to authenticated;

create or replace function public.capture_admin_activity_log()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  row_data jsonb;
  row_id text;
begin
  if tg_op = 'DELETE' then
    row_data := to_jsonb(old);
  else
    row_data := to_jsonb(new);
  end if;

  row_id := coalesce(row_data ->> 'id', row_data ->> 'uuid', row_data ->> 'table_id');

  insert into public.admin_activity_logs (table_name, record_id, operation, actor_id)
  values (tg_table_name, row_id, auth.uid());

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

-- Attach only to tables that exist in this installation.
do $$
declare
  target_table text;
  target_tables text[] := array[
    'orders',
    'products',
    'categories',
    'profiles',
    'reservations',
    'restaurant_tables',
    'dining_tables',
    'tickets',
    'banners',
    'discounts',
    'inventory_materials',
    'admin_notifications'
  ];
begin
  foreach target_table in array target_tables loop
    if to_regclass(format('public.%I', target_table)) is not null then
      execute format('drop trigger if exists admin_activity_audit on public.%I', target_table);
      execute format(
        'create trigger admin_activity_audit after insert or update or delete on public.%I for each row execute function public.capture_admin_activity_log()',
        target_table
      );
    end if;
  end loop;
end;
$$;
