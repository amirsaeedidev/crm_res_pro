-- SMS campaign effectiveness: per-recipient click tracking, coupon attribution and financial ROI.
alter table public.sms_campaigns
  add column if not exists discount_id uuid references public.discounts(id) on delete set null,
  add column if not exists attribution_window_days integer not null default 7 check (attribution_window_days between 1 and 90),
  add column if not exists sms_cost_per_message numeric(14,2) not null default 0 check (sms_cost_per_message >= 0),
  add column if not exists other_campaign_cost numeric(14,2) not null default 0 check (other_campaign_cost >= 0);

create index if not exists sms_campaigns_discount_id_idx on public.sms_campaigns(discount_id);

create table if not exists public.sms_campaign_tracking_tokens (
  id uuid primary key default gen_random_uuid(),
  outbox_id uuid not null unique references public.sms_outbox(id) on delete cascade,
  campaign_id uuid not null references public.sms_campaigns(id) on delete cascade,
  recipient_user_id uuid references public.profiles(id) on delete set null,
  token text not null unique,
  created_at timestamptz not null default now()
);
alter table public.sms_campaign_tracking_tokens enable row level security;
revoke all on public.sms_campaign_tracking_tokens from anon, authenticated, public;
grant all on public.sms_campaign_tracking_tokens to service_role;

create table if not exists public.sms_campaign_clicks (
  id bigint generated always as identity primary key,
  campaign_id uuid not null references public.sms_campaigns(id) on delete cascade,
  outbox_id uuid not null references public.sms_outbox(id) on delete cascade,
  recipient_user_id uuid references public.profiles(id) on delete set null,
  clicked_at timestamptz not null default now()
);
create index if not exists sms_campaign_clicks_campaign_clicked_idx on public.sms_campaign_clicks(campaign_id, clicked_at desc);
create index if not exists sms_campaign_clicks_user_clicked_idx on public.sms_campaign_clicks(recipient_user_id, clicked_at desc);
alter table public.sms_campaign_clicks enable row level security;
revoke all on public.sms_campaign_clicks from anon, authenticated, public;
grant all on public.sms_campaign_clicks to service_role;

create or replace function public.admin_create_sms_campaign(
  p_name text, p_customer_ids uuid[], p_normal_message text,
  p_pattern_body_id text default null, p_pattern_args text[] default '{}'::text[],
  p_audience_filter jsonb default '{}'::jsonb, p_discount_id uuid default null,
  p_sms_cost_per_message numeric default 0, p_other_campaign_cost numeric default 0,
  p_attribution_window_days integer default 7
) returns jsonb language plpgsql security definer set search_path = ''
as $function$
declare v_settings public.sms_settings%rowtype; v_campaign_id uuid; v_count integer := 0;
begin
  if not public.is_admin() then raise exception 'Administrator access required' using errcode='42501'; end if;
  select * into v_settings from public.sms_settings where id=1;
  if not found or not v_settings.sms_enabled or not v_settings.marketing_enabled then
    raise exception 'SMS marketing is disabled in settings' using errcode='22023';
  end if;
  if coalesce(array_length(p_customer_ids,1),0)=0 then raise exception 'At least one customer must be selected' using errcode='22023'; end if;
  if v_settings.send_mode='normal' and length(trim(coalesce(p_normal_message,'')))=0 then raise exception 'SMS message cannot be empty' using errcode='22023'; end if;
  if v_settings.send_mode='pattern' and length(trim(coalesce(p_pattern_body_id,v_settings.default_body_id,'')))=0 then raise exception 'Pattern Body ID is required' using errcode='22023'; end if;
  if p_discount_id is not null and not exists(select 1 from public.discounts d where d.id=p_discount_id and d.is_active=true) then
    raise exception 'Selected campaign discount is not active' using errcode='22023';
  end if;
  if coalesce(p_sms_cost_per_message,0)<0 or coalesce(p_other_campaign_cost,0)<0 then raise exception 'Campaign costs cannot be negative' using errcode='22023'; end if;
  if coalesce(p_attribution_window_days,7)<1 or coalesce(p_attribution_window_days,7)>90 then raise exception 'Attribution window must be between 1 and 90 days' using errcode='22023'; end if;

  insert into public.sms_campaigns(name,send_mode,normal_message,pattern_body_id,pattern_args,audience_filter,status,created_by,
    discount_id,sms_cost_per_message,other_campaign_cost,attribution_window_days)
  values(coalesce(nullif(trim(p_name),''),'کمپین پیامکی'),v_settings.send_mode,coalesce(p_normal_message,''),
    coalesce(nullif(trim(p_pattern_body_id),''),v_settings.default_body_id),coalesce(p_pattern_args,'{}'),
    coalesce(p_audience_filter,'{}'::jsonb),'queued',(select auth.uid()),p_discount_id,
    greatest(coalesce(p_sms_cost_per_message,0),0),greatest(coalesce(p_other_campaign_cost,0),0),coalesce(p_attribution_window_days,7))
  returning id into v_campaign_id;

  insert into public.sms_outbox(event_key,recipient_user_id,recipient_phone,send_mode,normal_message,pattern_body_id,
    pattern_args,status,attempts,max_attempts,campaign_id,idempotency_key)
  select 'marketing_campaign',p.id,trim(p.phone),v_settings.send_mode,coalesce(p_normal_message,''),
    coalesce(nullif(trim(p_pattern_body_id),''),v_settings.default_body_id),
    array(select replace(replace(arg,'{{name}}',coalesce(nullif(trim(coalesce(p.first_name,'')||' '||coalesce(p.last_name,'')),''),'مشتری')),
      '{{phone}}',p.phone) from unnest(coalesce(p_pattern_args,'{}'::text[])) as arg),
    'queued',0,v_settings.max_attempts,v_campaign_id,v_campaign_id::text||':'||p.id::text
  from public.profiles p where p.id=any(p_customer_ids) and p.role='customer' and p.status='active'
    and p.marketing_sms_opt_in=true and nullif(trim(coalesce(p.phone,'')),'') is not null
  on conflict(idempotency_key) do nothing;
  get diagnostics v_count = row_count;
  if v_count=0 then raise exception 'No selected customers have a phone and explicit marketing consent' using errcode='22023'; end if;
  update public.sms_campaigns set recipient_count=v_count where id=v_campaign_id;
  return jsonb_build_object('campaign_id',v_campaign_id,'recipient_count',v_count,'status','queued');
end;
$function$;

revoke all on function public.admin_create_sms_campaign(text,uuid[],text,text,text[],jsonb,uuid,numeric,numeric,integer) from public, anon;
grant execute on function public.admin_create_sms_campaign(text,uuid[],text,text,text[],jsonb,uuid,numeric,numeric,integer) to authenticated;

create or replace function public.admin_get_sms_campaign_effectiveness(p_start timestamptz, p_end timestamptz)
returns jsonb language plpgsql security definer set search_path = ''
as $function$
declare v_result jsonb;
begin
  if not public.is_admin() then raise exception 'Administrator access required' using errcode='42501'; end if;
  if p_start is null or p_end is null or p_end<=p_start then raise exception 'Invalid reporting date range' using errcode='22023'; end if;
  with selected_campaigns as (
    select c.* from public.sms_campaigns c where c.created_at>=p_start and c.created_at<p_end
  ),
  link_orders as (
    select o.id as order_id, click.campaign_id, 'link'::text as attribution_type
    from public.orders o
    join lateral (
      select cl.campaign_id,cl.clicked_at from public.sms_campaign_clicks cl
      join selected_campaigns sc on sc.id=cl.campaign_id
      where cl.recipient_user_id=o.user_id and cl.clicked_at < p_end and cl.clicked_at<=coalesce(o.completed_at,o.created_at)
        and cl.clicked_at>=coalesce(o.completed_at,o.created_at)-make_interval(days=>sc.attribution_window_days)
      order by cl.clicked_at desc limit 1
    ) click on true where o.status='completed' and coalesce(o.completed_at,o.created_at) < p_end
  ),
  coupon_orders as (
    select distinct o.id as order_id,sc.id as campaign_id,'coupon'::text as attribution_type
    from public.orders o join public.discounts d on upper(d.code)=upper(o.discount_code)
    join selected_campaigns sc on sc.discount_id=d.id
    where o.status='completed' and coalesce(o.completed_at,o.created_at) < p_end and o.created_at>=sc.created_at
      and o.created_at<=sc.created_at+make_interval(days=>sc.attribution_window_days)
  ),
  all_attributions as (
    select * from link_orders
    union all select co.* from coupon_orders co
    where not exists(select 1 from link_orders lo where lo.order_id=co.order_id)
  ),
  order_financials as (
    select a.campaign_id,count(distinct o.id)::integer as attributed_orders,
      coalesce(sum(o.subtotal_amount),0)::numeric as gross_sales,
      coalesce(sum(o.total_amount),0)::numeric as order_revenue,
      coalesce(sum(o.discount_amount),0)::numeric as discounts_given,
      coalesce(sum(ref.refund_amount),0)::numeric as refunds,
      coalesce(sum(cost.cogs),0)::numeric as cogs,
      count(distinct o.id) filter(where a.attribution_type='coupon')::integer as coupon_orders,
      count(distinct o.id) filter(where a.attribution_type='link')::integer as link_orders
    from all_attributions a join public.orders o on o.id=a.order_id
    left join lateral (select sum(r.amount) as refund_amount from public.order_refunds r
      where r.order_id=o.id and r.status in ('processed','completed','refunded')) ref on true
    left join lateral (select sum(abs(it.total_cost)) as cogs from public.inventory_transactions it
      where it.order_id=o.id and it.quantity_delta<0) cost on true
    group by a.campaign_id
  ),
  campaign_rows as (
    select sc.id,sc.name,sc.status,sc.created_at,sc.recipient_count,sc.sent_count,sc.failed_count,
      sc.discount_id,d.code as discount_code,coalesce(clicks.unique_clickers,0)::integer as unique_clickers,
      coalesce(clicks.total_clicks,0)::integer as total_clicks,coalesce(fin.attributed_orders,0)::integer as attributed_orders,
      coalesce(fin.coupon_orders,0)::integer as coupon_orders,coalesce(fin.link_orders,0)::integer as link_orders,
      coalesce(fin.gross_sales,0)::numeric as gross_sales,coalesce(fin.order_revenue,0)::numeric as order_revenue,
      coalesce(fin.discounts_given,0)::numeric as discounts_given,coalesce(fin.refunds,0)::numeric as refunds,
      coalesce(fin.cogs,0)::numeric as cogs,(sc.sent_count*sc.sms_cost_per_message)::numeric as sms_cost,
      sc.other_campaign_cost,
      (coalesce(fin.order_revenue,0)-coalesce(fin.refunds,0)-coalesce(fin.cogs,0)
        -(sc.sent_count*sc.sms_cost_per_message)-sc.other_campaign_cost)::numeric as net_profit,
      case when ((sc.sent_count*sc.sms_cost_per_message)+sc.other_campaign_cost)>0 then
        ((coalesce(fin.order_revenue,0)-coalesce(fin.refunds,0)-coalesce(fin.cogs,0)
          -(sc.sent_count*sc.sms_cost_per_message)-sc.other_campaign_cost)
          /((sc.sent_count*sc.sms_cost_per_message)+sc.other_campaign_cost)*100)::numeric else null end as roi_percent,
      sc.attribution_window_days
    from selected_campaigns sc left join public.discounts d on d.id=sc.discount_id
    left join lateral (select count(*)::integer as total_clicks,
      count(distinct coalesce(cl.recipient_user_id,cl.outbox_id))::integer as unique_clickers
      from public.sms_campaign_clicks cl where cl.campaign_id=sc.id and cl.clicked_at < p_end) clicks on true
    left join order_financials fin on fin.campaign_id=sc.id
  )
  select jsonb_build_object('summary',jsonb_build_object(
    'campaign_count',count(*),'recipients',coalesce(sum(recipient_count),0),
    'provider_accepted',coalesce(sum(sent_count),0),'failed',coalesce(sum(failed_count),0),
    'unique_clickers',coalesce(sum(unique_clickers),0),'attributed_orders',coalesce(sum(attributed_orders),0),
    'gross_sales',coalesce(sum(gross_sales),0),'order_revenue',coalesce(sum(order_revenue),0),
    'discounts_given',coalesce(sum(discounts_given),0),'refunds',coalesce(sum(refunds),0),
    'cogs',coalesce(sum(cogs),0),'sms_cost',coalesce(sum(sms_cost),0),
    'other_campaign_cost',coalesce(sum(other_campaign_cost),0),'net_profit',coalesce(sum(net_profit),0),
    'roi_percent',case when coalesce(sum(sms_cost+other_campaign_cost),0)>0
      then (sum(net_profit)/sum(sms_cost+other_campaign_cost)*100) else null end),
    'campaigns',coalesce(jsonb_agg(to_jsonb(campaign_rows) order by created_at desc),'[]'::jsonb))
  into v_result from campaign_rows;
  return coalesce(v_result,'{"summary":{},"campaigns":[]}'::jsonb);
end;
$function$;
revoke all on function public.admin_get_sms_campaign_effectiveness(timestamptz,timestamptz) from public,anon;
grant execute on function public.admin_get_sms_campaign_effectiveness(timestamptz,timestamptz) to authenticated;
