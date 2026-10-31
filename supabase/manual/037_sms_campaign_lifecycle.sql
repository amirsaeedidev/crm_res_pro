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

create or replace function public.admin_create_sms_campaign_scheduled(
  p_name text,p_customer_ids uuid[],p_normal_message text,
  p_pattern_body_id text default null,p_pattern_args text[] default '{}',
  p_audience_filter jsonb default '{}',p_discount_id uuid default null,
  p_sms_cost_per_message numeric default 0,p_other_campaign_cost numeric default 0,
  p_attribution_window_days integer default 7,p_scheduled_at timestamptz default now()
) returns jsonb language plpgsql security definer set search_path=''
as $
declare v_result jsonb; v_campaign_id uuid;
begin
  if not coalesce(public.is_admin(),false) then
    raise exception 'Administrator access required' using errcode='42501';
  end if;
  if p_scheduled_at is null or p_scheduled_at < now()-interval '1 minute' then
    raise exception 'Scheduled time must be now or in the future' using errcode='22023';
  end if;
  v_result:=public.admin_create_sms_campaign(
    p_name,p_customer_ids,p_normal_message,p_pattern_body_id,p_pattern_args,
    p_audience_filter,p_discount_id,p_sms_cost_per_message,p_other_campaign_cost,
    p_attribution_window_days
  );
  v_campaign_id:=(v_result->>'campaign_id')::uuid;
  update public.sms_campaigns set scheduled_at=p_scheduled_at,
    status=case when p_scheduled_at>now() then 'queued' else status end
   where id=v_campaign_id;
  return v_result||jsonb_build_object('scheduled_at',p_scheduled_at);
end;
$;
revoke all on function public.admin_create_sms_campaign_scheduled(text,uuid[],text,text,text[],jsonb,uuid,numeric,numeric,integer,timestamptz) from public,anon;
grant execute on function public.admin_create_sms_campaign_scheduled(text,uuid[],text,text,text[],jsonb,uuid,numeric,numeric,integer,timestamptz) to authenticated;


-- Finalizer keeps cancelled campaigns terminal and waits for delivery reports
-- after provider acceptance instead of treating acceptance as delivery.
create or replace function public.sms_finalize_attempt(
 p_outbox_id uuid,p_success boolean,p_provider_message_id text default null,
 p_response_code text default null,p_error_message text default null,p_duration_ms integer default null
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_row public.sms_outbox%rowtype; v_status text; v_delay integer; v_campaign_id uuid;
begin
 select * into v_row from public.sms_outbox where id=p_outbox_id for update;
 if not found then raise exception 'SMS outbox row not found'; end if;
 select retry_delay_seconds into v_delay from public.sms_settings where id=1;
 v_delay:=coalesce(v_delay,60);
 if p_success then v_status:='sent';
 elsif upper(coalesce(p_response_code,''))='UNKNOWN' then v_status:='failed';
 elsif v_row.attempts < v_row.max_attempts then v_status:='retry';
 else v_status:='failed'; end if;

 insert into public.sms_attempt_logs(outbox_id,attempt_no,success,provider_message_id,response_code,error_message,duration_ms)
 values(v_row.id,v_row.attempts,coalesce(p_success,false),p_provider_message_id,left(p_response_code,100),
   left(p_error_message,500),greatest(coalesce(p_duration_ms,0),0))
 on conflict(outbox_id,attempt_no) do update set success=excluded.success,
   provider_message_id=excluded.provider_message_id,response_code=excluded.response_code,
   error_message=excluded.error_message,duration_ms=excluded.duration_ms;

 update public.sms_outbox set status=v_status,
   provider_message_id=case when p_success then p_provider_message_id else provider_message_id end,
   sent_at=case when p_success then now() else sent_at end,
   delivery_status=case when p_success then 'pending' else delivery_status end,
   last_error=case when p_success then null else left(p_error_message,500) end,
   next_attempt_at=case when v_status='retry' then now()+make_interval(secs=>v_delay) else next_attempt_at end,
   updated_at=now() where id=v_row.id;

 v_campaign_id:=v_row.campaign_id;
 if v_campaign_id is not null then
  update public.sms_campaigns c set
   sent_count=(select count(*) from public.sms_outbox o where o.campaign_id=v_campaign_id and o.status='sent'),
   failed_count=(select count(*) from public.sms_outbox o where o.campaign_id=v_campaign_id and o.status='failed'),
   status=case when c.status='cancelled' then 'cancelled'
     when exists(select 1 from public.sms_outbox o where o.campaign_id=v_campaign_id and o.status in ('queued','retry','sending')) then 'sending'
     when exists(select 1 from public.sms_outbox o where o.campaign_id=v_campaign_id and o.status='sent') then 'completed'
     else 'failed' end,
   started_at=coalesce(c.started_at,now()),
   completed_at=case when c.status='cancelled' then coalesce(c.completed_at,now())
     when not exists(select 1 from public.sms_outbox o where o.campaign_id=v_campaign_id and o.status in ('queued','retry','sending')) then now()
     else null end
   where c.id=v_campaign_id;
 end if;
 return jsonb_build_object('id',v_row.id,'status',v_status,'attempts',v_row.attempts,'max_attempts',v_row.max_attempts);
end;
$$;
