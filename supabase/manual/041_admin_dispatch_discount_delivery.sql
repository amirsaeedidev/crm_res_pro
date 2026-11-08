
create or replace function public.admin_dispatch_discount_delivery(
  p_discount_id uuid,
  p_channels text[],
  p_source_campaign_id uuid default null
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_discount public.discounts%rowtype;
  v_campaign_id uuid;
  v_customer_ids uuid[];
  v_notification_count integer := 0;
  v_banner_id uuid;
  v_sms_result jsonb;
  v_channel_results jsonb := '{}'::jsonb;
  v_success_channels integer := 0;
  v_failed_channels integer := 0;
  v_target_count integer := 0;
  v_sent_count integer := 0;
  v_failed_count integer := 0;
  v_status text;
begin
  if auth.uid() is null or not coalesce((select public.is_admin()), false) then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if coalesce(cardinality(p_channels), 0) = 0
     or not (p_channels <@ array['banner','notification','sms']::text[]) then
    raise exception 'At least one valid delivery channel is required' using errcode = '22023';
  end if;

  select * into v_discount from public.discounts
  where id = p_discount_id and is_active = true;
  if not found then raise exception 'Active discount not found' using errcode = 'P0002'; end if;

  if v_discount.restricted_to_customers then
    select coalesce(array_agg(t.user_id), '{}'::uuid[]) into v_customer_ids
    from public.discount_customer_targets t where t.discount_id = p_discount_id;
  else
    select coalesce(array_agg(p.id), '{}'::uuid[]) into v_customer_ids
    from public.profiles p where p.role = 'customer' and p.status = 'active';
  end if;

  insert into public.admin_notification_campaigns (
    campaign_type,title,body,audience,delivery_channels,status,discount_id,source_campaign_id,metadata
  ) values (
    'discount',
    coalesce(nullif(btrim(v_discount.title),''),'کد تخفیف'),
    'کد تخفیف شما: ' || v_discount.code ||
      case when nullif(btrim(coalesce(v_discount.description,'')),'') is null
        then '' else E'\n' || left(v_discount.description,300) end,
    case when v_discount.restricted_to_customers then 'targeted_discount' else 'all_customers' end,
    (select array_agg(distinct ch.channel order by ch.channel) from unnest(p_channels) as ch(channel)),
    'sending',p_discount_id,p_source_campaign_id,
    jsonb_build_object('discount_code',v_discount.code)
  ) returning id into v_campaign_id;

  if 'notification' = any(p_channels) then
    insert into public.customer_notifications (
      user_id,title,body,notification_type,entity_table,entity_id,event_key,priority,audience,metadata
    )
    select p.id,
      coalesce(nullif(btrim(v_discount.title),''),'تخفیف ویژه برای شما'),
      'کد تخفیف شما: ' || v_discount.code ||
        case when nullif(btrim(coalesce(v_discount.description,'')),'') is null
          then '' else E'\n' || left(v_discount.description,300) end,
      'discount','discounts',p_discount_id,
      'discount:' || p_discount_id::text || ':campaign:' || v_campaign_id::text || ':user:' || p.id::text,
      'normal','all_customers',
      jsonb_build_object('discount_code',v_discount.code,'campaign_id',v_campaign_id)
    from public.profiles p
    where p.id = any(v_customer_ids) and p.role='customer' and p.status='active'
      and not exists (
        select 1 from public.customer_notifications existing
        where existing.event_key='discount:' || p_discount_id::text || ':user:' || p.id::text
      )
    on conflict(event_key) do nothing;
    get diagnostics v_notification_count = row_count;
    v_target_count := v_target_count + coalesce(cardinality(v_customer_ids),0);
    v_sent_count := v_sent_count + v_notification_count;
    if v_notification_count > 0 then
      v_success_channels := v_success_channels + 1;
      v_channel_results := v_channel_results || jsonb_build_object('notification',
        jsonb_build_object('status','completed','recipient_count',v_notification_count));
    else
      v_failed_channels := v_failed_channels + 1;
      v_failed_count := v_failed_count + 1;
      v_channel_results := v_channel_results || jsonb_build_object('notification',
        jsonb_build_object('status','failed','recipient_count',0,'error','No eligible recipients'));
    end if;
  end if;

  if 'banner' = any(p_channels) then
    begin
      insert into public.banners(title,image_url,sort_order,is_active,subtitle,promo_title,discount_code,logo_url)
      select coalesce(nullif(btrim(v_discount.title),''),'تخفیف ویژه'),source.image_url,
        coalesce((select max(sort_order)+1 from public.banners),0),true,
        coalesce(v_discount.description,''),coalesce(nullif(btrim(v_discount.title),''),'تخفیف ویژه'),
        v_discount.code,source.logo_url
      from (
        select image_url,logo_url from public.banners
        where is_active=true and nullif(btrim(image_url),'') is not null
        order by sort_order,created_at desc limit 1
      ) source
      returning id into v_banner_id;
      if v_banner_id is null then raise exception 'No active banner image is available'; end if;
      v_target_count := v_target_count+1;
      v_sent_count := v_sent_count+1;
      v_success_channels := v_success_channels+1;
      v_channel_results := v_channel_results || jsonb_build_object('banner',
        jsonb_build_object('status','completed','banner_id',v_banner_id));
    exception when others then
      v_failed_channels := v_failed_channels+1;
      v_failed_count := v_failed_count+1;
      v_channel_results := v_channel_results || jsonb_build_object('banner',
        jsonb_build_object('status','failed','error',left(sqlerrm,300)));
    end;
  end if;

  if 'sms' = any(p_channels) then
    begin
      v_sms_result := public.admin_create_sms_campaign(
        coalesce(nullif(btrim(v_discount.title),''),'کمپین کد تخفیف'),
        v_customer_ids,'کد تخفیف شما: ' || v_discount.code,null,array[v_discount.code],
        jsonb_build_object('source','discount_delivery','discount_id',p_discount_id),
        p_discount_id,0,0,7
      );
      v_target_count := v_target_count+coalesce((v_sms_result->>'recipient_count')::integer,0);
      v_sent_count := v_sent_count+coalesce((v_sms_result->>'recipient_count')::integer,0);
      v_success_channels := v_success_channels+1;
      v_channel_results := v_channel_results || jsonb_build_object('sms',
        jsonb_build_object('status','queued','sms_campaign_id',v_sms_result->>'campaign_id',
          'recipient_count',coalesce((v_sms_result->>'recipient_count')::integer,0)));
    exception when others then
      v_failed_channels := v_failed_channels+1;
      v_failed_count := v_failed_count+1;
      v_channel_results := v_channel_results || jsonb_build_object('sms',
        jsonb_build_object('status','failed','error',left(sqlerrm,300)));
    end;
  end if;

  v_status := case when v_success_channels>0 and v_failed_channels=0 then 'completed'
    when v_success_channels>0 then 'partial' else 'failed' end;

  update public.admin_notification_campaigns
  set status=v_status,banner_id=v_banner_id,
    sms_campaign_id=case when v_channel_results ? 'sms'
      and v_channel_results->'sms'->>'sms_campaign_id' is not null
      then (v_channel_results->'sms'->>'sms_campaign_id')::uuid else null end,
    target_count=v_target_count,sent_count=v_sent_count,failed_count=v_failed_count,
    channel_results=v_channel_results,
    sent_at=case when v_success_channels>0 then now() else null end,updated_at=now()
  where id=v_campaign_id;

  return jsonb_build_object('success',v_success_channels>0,'campaign_id',v_campaign_id,
    'status',v_status,'target_count',v_target_count,'sent_count',v_sent_count,
    'failed_count',v_failed_count,'channel_results',v_channel_results);
end;
$$;

revoke all on function public.admin_dispatch_discount_delivery(uuid,text[],uuid) from public,anon;
grant execute on function public.admin_dispatch_discount_delivery(uuid,text[],uuid) to authenticated;
