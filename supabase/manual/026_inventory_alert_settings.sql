begin;
create table if not exists public.inventory_alert_settings (
 id boolean primary key default true check(id),
 default_reorder_level numeric(14,3) not null default 1 check(default_reorder_level>=0),
 near_empty_multiplier numeric(5,2) not null default 1.50 check(near_empty_multiplier>=1 and near_empty_multiplier<=10),
 show_low_stock_alerts boolean not null default true,
 show_near_empty_alerts boolean not null default true,
 include_zero_stock boolean not null default true,
 updated_by uuid references auth.users(id) on delete set null,
 updated_at timestamptz not null default now()
);
insert into public.inventory_alert_settings(id) values(true) on conflict(id) do nothing;
alter table public.inventory_alert_settings enable row level security;
drop policy if exists inventory_alert_settings_admin_all on public.inventory_alert_settings;
create policy inventory_alert_settings_admin_all on public.inventory_alert_settings
for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
grant select,insert,update on public.inventory_alert_settings to authenticated;
commit;