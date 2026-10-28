-- Shared restaurant business settings for both the CRM and restaurant app.
-- Run this manually in Supabase SQL Editor before using CRM Settings.

begin;

create table if not exists public.restaurant_settings (
  id text primary key default 'restaurant' check (id = 'restaurant'),
  company_name text not null default '',
  company_phone text not null default '',
  company_address text not null default '',
  min_delivery_amount numeric(14, 2) not null default 0 check (min_delivery_amount >= 0),
  fixed_delivery_fee numeric(14, 2) not null default 0 check (fixed_delivery_fee >= 0),
  primary_color bigint not null default 4280640491,
  secondary_color bigint not null default 4279150057,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

alter table public.restaurant_settings enable row level security;

grant select on public.restaurant_settings to anon, authenticated;
grant insert, update on public.restaurant_settings to authenticated;

drop policy if exists restaurant_settings_public_read on public.restaurant_settings;
create policy restaurant_settings_public_read
  on public.restaurant_settings for select
  to anon, authenticated
  using (true);

drop policy if exists restaurant_settings_admin_insert on public.restaurant_settings;
create policy restaurant_settings_admin_insert
  on public.restaurant_settings for insert
  to authenticated
  with check ((select public.is_admin()));

drop policy if exists restaurant_settings_admin_update on public.restaurant_settings;
create policy restaurant_settings_admin_update
  on public.restaurant_settings for update
  to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

insert into public.restaurant_settings (id)
values ('restaurant')
on conflict (id) do nothing;

commit;
