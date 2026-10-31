-- SMS campaign lifecycle: scheduling, idempotent dispatch, opt-out, delivery,
-- click tracking and discount redemption attribution.
begin;

alter table public.sms_campaigns
  add column if not exists scheduled_at timestamptz not null default now(),
  add column if not exists delivered_count integer not null default 0 check (delivered_count >= 0),
  add column if not exists cancelled_at timestamptz;

alter table public.sms_outbox
  add column if not exists delivered_at timestamptz,
  add column if not exists delivery_status text not null default 'unknown'
    check (delivery_status in ('unknown','pending','delivered','undelivered')),
  add column if not exists delivery_code text,
  add column if not exists delivery_error text,
  add column if not exists delivery_reported_at timestamptz;

alter table public.sms_campaign_tracking_tokens
  add column if not exists destination_url text;

create unique index if not exists sms_campaign_tracking_token_unique
  on public.sms_campaign_tracking_tokens(token);
create unique index if not exists sms_campaign_tracking_outbox_destination_unique
  on public.sms_campaign_tracking_tokens(outbox_id,destination_url)
  where destination_url is not null;
create index if not exists idx_sms_campaigns_scheduled
  on public.sms_campaigns(scheduled_at) where status in ('queued','sending');
create index if not exists idx_sms_outbox_provider_message
  on public.sms_outbox(provider_message_id) where provider_message_id is not null;
create index if not exists idx_sms_outbox_campaign_status
  on public.sms_outbox(campaign_id,status);

create or replace function public.sms_claim_pending_batch(p_limit integer default 20)
returns setof public.sms_outbox
language plpgsql security definer set search_path = ''
as $$
begin
  update public.sms_outbox o
     set status='cancelled',
         last_error='لغو شد: مشتری دریافت پیام تبلیغاتی را غیرفعال کرده است.',
         updated_at=now()
   where o.status in ('queued','retry')
     and o.event_key='marketing_campaign'
     and o.recipient_user_id is not null
     and not exists (
       select 1 from public.profiles p
       where p.id=o.recipient_user_id and p.role='customer'
         and p.status='active' and p.marketing_sms_opt_in=true
     );

  update public.sms_campaigns c
     set status='cancelled',cancelled_at=coalesce(c.cancelled_at,now()),completed_at=now()
   where c.status in ('queued','sending')
     and not exists (
       select 1 from public.sms_outbox o
       where o.campaign_id=c.id and o.status in ('queued','retry','sending')
     )
     and exists (select 1 from public.sms_outbox o where o.campaign_id=c.id and o.status='cancelled');

  return query
  with picked as (
    select o.id
      from public.sms_outbox o
      left join public.sms_campaigns c on c.id=o.campaign_id
     where o.status in ('queued','retry')
       and o.next_attempt_at<=now()
       and (o.campaign_id is null or (c.status in ('queued','sending') and c.scheduled_at<=now()))
       and (
         o.event_key<>'marketing_campaign'
         or exists (
           select 1 from public.profiles p
           where p.id=o.recipient_user_id and p.role='customer'
             and p.status='active' and p.marketing_sms_opt_in=true
         )
       )
     order by o.next_attempt_at,o.created_at
     for update of o skip locked
     limit greatest(1,least(coalesce(p_limit,20),100))
  ), updated as (
    update public.sms_outbox o
       set status='sending',attempts=o.attempts+1,updated_at=now()
      from picked where o.id=picked.id
    returning o.*
  )
  select * from updated order by created_at;
end;
$$;

create or replace function public.customer_set_marketing_sms_opt_in(p_opt_in boolean)
returns jsonb language plpgsql security invoker set search_path = ''
as $$
declare v_uid uuid:=auth.uid();
begin
  if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  update public.profiles
     set marketing_sms_opt_in=coalesce(p_opt_in,false),
         marketing_sms_opt_in_at=case when coalesce(p_opt_in,false) then now() else null end,
         updated_at=now()
   where id=v_uid and role='customer';
  if not found then raise exception 'Customer profile not found' using errcode='P0002'; end if;
  if not coalesce(p_opt_in,false) then
    update public.sms_outbox
       set status='cancelled',
           last_error='لغو شد: مشتری دریافت پیام تبلیغاتی را غیرفعال کرده است.',
           updated_at=now()
     where recipient_user_id=v_uid and event_key='marketing_campaign'
       and status in ('queued','retry');
  end if;
  return jsonb_build_object('success',true,'marketing_sms_opt_in',coalesce(p_opt_in,false));
end;
$$;
revoke all on function public.customer_set_marketing_sms_opt_in(boolean) from public,anon;
grant execute on function public.customer_set_marketing_sms_opt_in(boolean) to authenticated;

create or replace function public.admin_cancel_sms_campaign(p_campaign_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_cancelled integer;
begin
  if auth.uid() is null or not coalesce(public.is_admin(),false) then
    raise exception 'Administrator access required' using errcode='42501';
  end if;
  update public.sms_outbox set status='cancelled',last_error='کمپین توسط مدیر لغو شد.',updated_at=now()
   where campaign_id=p_campaign_id and status in ('queued','retry');
  get diagnostics v_cancelled=row_count;
  update public.sms_campaigns set status='cancelled',cancelled_at=now(),completed_at=now()
   where id=p_campaign_id and status in ('draft','queued','sending');
  if not found then raise exception 'Campaign not found or already finished' using errcode='P0002'; end if;
  return jsonb_build_object('success',true,'cancelled_messages',v_cancelled);
end;
$$;
revoke all on function public.admin_cancel_sms_campaign(uuid) from public,anon;
grant execute on function public.admin_cancel_sms_campaign(uuid) to authenticated;

create or replace function public.sms_apply_delivery_report(
  p_provider_message_id text,p_status text,p_delivery_code text default null,p_error text default null
) returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_id uuid; v_campaign uuid;
begin
  if p_provider_message_id is null or length(trim(p_provider_message_id))=0 then
    raise exception 'Provider message id is required' using errcode='22023';
  end if;
  if p_status not in ('delivered','undelivered') then
    raise exception 'Invalid delivery status' using errcode='22023';
  end if;
  update public.sms_outbox
     set delivery_status=p_status,
         delivered_at=case when p_status='delivered' then coalesce(delivered_at,now()) else delivered_at end,
         delivery_code=left(p_delivery_code,100),
         delivery_error=left(p_error,500),
         delivery_reported_at=now(),updated_at=now()
   where provider_message_id=trim(p_provider_message_id)
   returning id,campaign_id into v_id,v_campaign;
  if v_id is null then return jsonb_build_object('success',false,'reason','message_not_found'); end if;
  if v_campaign is not null then
    update public.sms_campaigns c set delivered_count=(
      select count(*) from public.sms_outbox o
      where o.campaign_id=v_campaign and o.delivery_status='delivered'
    ) where c.id=v_campaign;
  end if;
  return jsonb_build_object('success',true,'outbox_id',v_id,'status',p_status);
end;
$$;
revoke all on function public.sms_apply_delivery_report(text,text,text,text) from public,anon,authenticated;
grant execute on function public.sms_apply_delivery_report(text,text,text,text) to service_role;

create table if not exists public.sms_campaign_discount_redemptions (
  id bigint generated always as identity primary key,
  campaign_id uuid not null references public.sms_campaigns(id) on delete cascade,
  order_id uuid not null references public.orders(id) on delete cascade,
  customer_id uuid,
  discount_code text not null,
  redeemed_at timestamptz not null default now(),
  unique(campaign_id,order_id)
);
alter table public.sms_campaign_discount_redemptions enable row level security;
drop policy if exists sms_campaign_discount_redemptions_admin_read on public.sms_campaign_discount_redemptions;
create policy sms_campaign_discount_redemptions_admin_read on public.sms_campaign_discount_redemptions
for select to authenticated using ((select public.is_admin()));
grant select on public.sms_campaign_discount_redemptions to authenticated;

create or replace function public.sms_capture_campaign_discount_redemption()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.status='completed' and nullif(trim(coalesce(new.discount_code,'')),'') is not null then
    insert into public.sms_campaign_discount_redemptions(campaign_id,order_id,customer_id,discount_code)
    select c.id,new.id,new.user_id,d.code
      from public.sms_campaigns c join public.discounts d on d.id=c.discount_id
     where upper(d.code)=upper(trim(new.discount_code))
    on conflict(campaign_id,order_id) do nothing;
  end if;
  return new;
end;
$$;
revoke all on function public.sms_capture_campaign_discount_redemption() from public,anon,authenticated;
drop trigger if exists trg_sms_capture_campaign_discount_redemption on public.orders;
create trigger trg_sms_capture_campaign_discount_redemption
after insert or update of status,discount_code on public.orders
for each row execute function public.sms_capture_campaign_discount_redemption();

drop policy if exists sms_campaign_clicks_admin_read on public.sms_campaign_clicks;
create policy sms_campaign_clicks_admin_read on public.sms_campaign_clicks
for select to authenticated using ((select public.is_admin()));
drop policy if exists sms_campaign_tracking_tokens_admin_read on public.sms_campaign_tracking_tokens;
create policy sms_campaign_tracking_tokens_admin_read on public.sms_campaign_tracking_tokens
for select to authenticated using ((select public.is_admin()));
grant select on public.sms_campaign_clicks,public.sms_campaign_tracking_tokens to authenticated;

commit;

-- The scheduled wrapper admin_create_sms_campaign_scheduled(...) delegates to
-- the existing validated campaign RPC and updates scheduled_at in the same transaction.
