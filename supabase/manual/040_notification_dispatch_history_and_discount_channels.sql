-- Unified admin notification dispatch history and multi-channel discount publishing.
-- Apply after 019_notification_audience_and_priority and 037_sms_campaign_lifecycle.

begin;

create table if not exists public.admin_notification_dispatches (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null default '',
  audience text not null check (audience in ('admins','all_customers','inactive_30d','targeted_discount')),
  priority text not null default 'normal' check (priority in ('normal','high','urgent')),
  source_type text not null check (source_type in ('manual','discount')),
  source_id uuid,
  channels text[] not null default array['notification']::text[],
  recipient_count integer not null default 0 check (recipient_count >= 0),
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists admin_notification_dispatches_created_idx
  on public.admin_notification_dispatches(created_at desc);
create index if not exists admin_notification_dispatches_source_idx
  on public.admin_notification_dispatches(source_type, source_id, created_at desc);

alter table public.admin_notification_dispatches enable row level security;
drop policy if exists admin_notification_dispatches_admin_read on public.admin_notification_dispatches;
create policy admin_notification_dispatches_admin_read
  on public.admin_notification_dispatches
  for select to authenticated
  using ((select public.is_admin()));

revoke all on public.admin_notification_dispatches from public, anon;
grant select on public.admin_notification_dispatches to authenticated;

create or replace function public.admin_send_notification(
  p_title text, p_body text, p_audience text, p_priority text default 'normal'
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_title text := pg_catalog.btrim(coalesce(p_title, ''));
  v_body text := pg_catalog.btrim(coalesce(p_body, ''));
  v_count integer := 0;
  v_dispatch_id uuid;
begin
  if auth.uid() is null or not coalesce(public.is_admin(), false) then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if v_title = '' or pg_catalog.length(v_title) > 160 then
    raise exception 'Invalid title' using errcode = '22023';
  end if;
  if v_body = '' or pg_catalog.length(v_body) > 4000 then
    raise exception 'Invalid message' using errcode = '22023';
  end if;
  if p_priority not in ('normal', 'high', 'urgent') then
    raise exception 'Invalid priority' using errcode = '22023';
  end if;

  if p_audience = 'admins' then
    insert into public.admin_notifications(title,body,notification_type,priority,audience)
    values(v_title,v_body,'general',p_priority,'admins');
    get diagnostics v_count = row_count;
  elsif p_audience = 'all_customers' then
    insert into public.customer_notifications(user_id,title,body,notification_type,priority,audience)
    select id,v_title,v_body,'general',p_priority,p_audience
      from public.profiles where role='customer' and status='active';
    get diagnostics v_count = row_count;
  elsif p_audience = 'inactive_30d' then
    insert into public.customer_notifications(user_id,title,body,notification_type,priority,audience)
    select p.id,v_title,v_body,'general',p_priority,p_audience
      from public.profiles p
     where p.role='customer' and p.status='active'
       and not exists (
         select 1 from public.orders o
          where o.user_id=p.id
            and o.created_at >= pg_catalog.now() - interval '30 days'
            and o.status <> 'cancelled'
       );
    get diagnostics v_count = row_count;
  else
    raise exception 'Invalid audience' using errcode = '22023';
  end if;

  insert into public.admin_notification_dispatches(
    title,body,audience,priority,source_type,channels,recipient_count,created_by
  ) values (
    v_title,v_body,p_audience,p_priority,'manual',array['notification']::text[],v_count,auth.uid()
  ) returning id into v_dispatch_id;

  return pg_catalog.jsonb_build_object(
    'success',true,'recipient_count',v_count,'audience',p_audience,
    'priority',p_priority,'dispatch_id',v_dispatch_id
  );
end;
$$;

create or replace function public.admin_publish_discount(
  p_discount_id uuid,
  p_channels text[],
  p_sms_message text default null
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_discount public.discounts%rowtype;
  v_channels text[] := coalesce(p_channels, array[]::text[]);
  v_body text;
  v_notification_count integer := 0;
  v_sms_customer_ids uuid[] := array[]::uuid[];
  v_sms_result jsonb := '{}'::jsonb;
  v_sms_campaign_id uuid;
  v_sms_count integer := 0;
  v_banner_id uuid;
  v_dispatch_id uuid;
  v_total_recipients integer := 0;
  v_audience text;
begin
  if auth.uid() is null or not coalesce(public.is_admin(), false) then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if p_discount_id is null or cardinality(v_channels)=0 then
    raise exception 'Select a discount and at least one delivery channel' using errcode = '22023';
  end if;
  if exists (
    select 1 from unnest(v_channels) c
     where c not in ('banner','notification','sms')
  ) then
    raise exception 'Invalid discount delivery channel' using errcode = '22023';
  end if;

  select * into v_discount
    from public.discounts
   where id=p_discount_id and is_active=true;
  if not found then
    raise exception 'Active discount not found' using errcode = 'P0002';
  end if;

  if 'banner'=any(v_channels) and coalesce(v_discount.restricted_to_customers,false) then
    raise exception 'A customer-restricted discount cannot be published as a public banner' using errcode = '22023';
  end if;

  v_body := coalesce(
    nullif(pg_catalog.btrim(coalesce(v_discount.description,'')),''),
    'کد تخفیف '||v_discount.code||' برای شما فعال شد.'
  );

  if 'banner'=any(v_channels) then
    insert into public.banners(title,subtitle,promo_title,discount_code,is_active,sort_order)
    values (
      v_discount.title,
      v_body,
      'کد تخفیف '||v_discount.code,
      v_discount.code,
      true,
      0
    ) returning id into v_banner_id;
  end if;

  if 'notification'=any(v_channels) then
    if coalesce(v_discount.restricted_to_customers,false) then
      insert into public.customer_notifications(
        user_id,title,body,notification_type,priority,audience,entity_table,entity_id
      )
      select t.user_id,
             'تخفیف جدید: '||v_discount.title,
             v_body||E'\nکد تخفیف: '||v_discount.code,
             'general','normal','all_customers','discounts',v_discount.id
        from public.discount_customer_targets t
        join public.profiles p on p.id=t.user_id
       where t.discount_id=v_discount.id
         and p.role='customer' and p.status='active';
    else
      insert into public.customer_notifications(
        user_id,title,body,notification_type,priority,audience,entity_table,entity_id
      )
      select p.id,
             'تخفیف جدید: '||v_discount.title,
             v_body||E'\nکد تخفیف: '||v_discount.code,
             'general','normal','all_customers','discounts',v_discount.id
        from public.profiles p
       where p.role='customer' and p.status='active';
    end if;
    get diagnostics v_notification_count = row_count;
    v_total_recipients := v_total_recipients + v_notification_count;
  end if;

  if 'sms'=any(v_channels) then
    select coalesce(array_agg(p.id),array[]::uuid[])
      into v_sms_customer_ids
      from public.profiles p
     where p.role='customer'
       and p.status='active'
       and p.marketing_sms_opt_in=true
       and nullif(pg_catalog.btrim(coalesce(p.phone,'')),'') is not null
       and (
         not coalesce(v_discount.restricted_to_customers,false)
         or exists (
           select 1 from public.discount_customer_targets t
            where t.discount_id=v_discount.id and t.user_id=p.id
         )
       );

    v_sms_count := coalesce(cardinality(v_sms_customer_ids),0);
    if v_sms_count > 0 then
      v_sms_result := public.admin_create_sms_campaign_scheduled(
        p_name => 'تخفیف: '||v_discount.title,
        p_customer_ids => v_sms_customer_ids,
        p_normal_message => coalesce(
          nullif(pg_catalog.btrim(coalesce(p_sms_message,'')),''),
          'کد تخفیف '||v_discount.code||' برای شما فعال شد. '||v_body
        ),
        p_pattern_body_id => null,
        p_pattern_args => array[]::text[],
        p_audience_filter => pg_catalog.jsonb_build_object('discount_id',v_discount.id,'source','discount_form'),
        p_discount_id => v_discount.id,
        p_sms_cost_per_message => 0,
        p_other_campaign_cost => 0,
        p_attribution_window_days => 7,
        p_scheduled_at => pg_catalog.now()
      );
      v_sms_campaign_id := nullif(v_sms_result->>'campaign_id','')::uuid;
      v_total_recipients := v_total_recipients + v_sms_count;
    end if;
  end if;

  v_audience := case when coalesce(v_discount.restricted_to_customers,false)
    then 'targeted_discount' else 'all_customers' end;

  insert into public.admin_notification_dispatches(
    title,body,audience,priority,source_type,source_id,channels,
    recipient_count,metadata,created_by
  ) values (
    'انتشار تخفیف: '||v_discount.title,
    v_body,
    v_audience,
    'normal',
    'discount',
    v_discount.id,
    v_channels,
    v_total_recipients,
    pg_catalog.jsonb_build_object(
      'banner_id',v_banner_id,
      'notification_count',v_notification_count,
      'sms_campaign_id',v_sms_campaign_id,
      'sms_recipient_count',v_sms_count
    ),
    auth.uid()
  ) returning id into v_dispatch_id;

  return pg_catalog.jsonb_build_object(
    'success',true,
    'dispatch_id',v_dispatch_id,
    'banner_id',v_banner_id,
    'notification_count',v_notification_count,
    'sms_campaign_id',v_sms_campaign_id,
    'sms_recipient_count',v_sms_count,
    'channels',v_channels
  );
end;
$$;

create or replace function public.admin_resend_notification(p_dispatch_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_dispatch public.admin_notification_dispatches%rowtype;
begin
  if auth.uid() is null or not coalesce(public.is_admin(), false) then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;

  select * into v_dispatch
    from public.admin_notification_dispatches
   where id=p_dispatch_id;
  if not found then
    raise exception 'Notification history entry not found' using errcode = 'P0002';
  end if;

  if v_dispatch.source_type='discount' then
    return public.admin_publish_discount(v_dispatch.source_id,v_dispatch.channels,null);
  end if;

  return public.admin_send_notification(
    v_dispatch.title,v_dispatch.body,v_dispatch.audience,v_dispatch.priority
  );
end;
$$;

revoke all on function public.admin_send_notification(text,text,text,text) from public,anon;
revoke all on function public.admin_publish_discount(uuid,text[],text) from public,anon;
revoke all on function public.admin_resend_notification(uuid) from public,anon;
grant execute on function public.admin_send_notification(text,text,text,text) to authenticated;
grant execute on function public.admin_publish_discount(uuid,text[],text) to authenticated;
grant execute on function public.admin_resend_notification(uuid) to authenticated;

commit;
