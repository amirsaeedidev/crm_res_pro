-- Discount delivery channels and unified admin notification campaign history.
-- Applied to the Food Delivery Supabase project before the Flutter integration.

alter table public.discounts
  add column if not exists delivery_channels text[] not null default array['notification']::text[];

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.discounts'::regclass
      and conname = 'discounts_delivery_channels_valid'
  ) then
    alter table public.discounts
      add constraint discounts_delivery_channels_valid
      check (
        cardinality(delivery_channels) > 0
        and delivery_channels <@ array['banner','notification','sms']::text[]
      );
  end if;
end
$$;

create table if not exists public.admin_notification_campaigns (
  id uuid primary key default gen_random_uuid(),
  campaign_type text not null default 'manual'
    check (campaign_type in ('manual','discount')),
  title text not null check (length(btrim(title)) > 0),
  body text not null default '',
  audience text not null default 'all_customers',
  delivery_channels text[] not null
    check (
      cardinality(delivery_channels) > 0
      and delivery_channels <@ array['banner','notification','sms']::text[]
    ),
  status text not null default 'queued'
    check (status in ('queued','sending','completed','partial','failed','cancelled')),
  discount_id uuid references public.discounts(id) on delete set null,
  banner_id uuid references public.banners(id) on delete set null,
  sms_campaign_id uuid references public.sms_campaigns(id) on delete set null,
  source_campaign_id uuid references public.admin_notification_campaigns(id) on delete set null,
  target_count integer not null default 0 check (target_count >= 0),
  sent_count integer not null default 0 check (sent_count >= 0),
  failed_count integer not null default 0 check (failed_count >= 0),
  channel_results jsonb not null default '{}'::jsonb
    check (jsonb_typeof(channel_results) = 'object'),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint admin_notification_campaign_discount_type_check
    check (
      (campaign_type = 'manual' and discount_id is null)
      or campaign_type = 'discount'
    )
);

create index if not exists idx_admin_notification_campaigns_created_at
  on public.admin_notification_campaigns (created_at desc);
create index if not exists idx_admin_notification_campaigns_discount_id
  on public.admin_notification_campaigns (discount_id)
  where discount_id is not null;
create index if not exists idx_admin_notification_campaigns_status
  on public.admin_notification_campaigns (status, created_at desc);

alter table public.admin_notification_campaigns enable row level security;
revoke all on public.admin_notification_campaigns from anon, public;
grant select, insert, update, delete on public.admin_notification_campaigns to authenticated;

drop policy if exists admin_notification_campaigns_admin_all on public.admin_notification_campaigns;
create policy admin_notification_campaigns_admin_all
  on public.admin_notification_campaigns
  for all
  to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

grant select, insert, update on public.discounts to authenticated;
