-- Resending a segment campaign reuses the persisted eligibility snapshot instead of recalculating the segment.
create or replace function public.admin_dispatch_discount_delivery_v2(
  p_discount_id uuid,p_channels text[],p_audience text,
  p_customer_ids uuid[] default '{}'::uuid[],
  p_source_campaign_id uuid default null,
  p_request_key uuid default null
) returns jsonb language plpgsql security invoker set search_path=''
as $function$
declare
  v_discount public.discounts%rowtype;
  v_customer_ids uuid[]:='{}'::uuid[];
  v_result jsonb;
  v_campaign_id uuid;
  v_existing public.admin_notification_campaigns%rowtype;
begin
  if auth.uid() is null or not coalesce((select public.is_admin()),false) then raise exception 'Administrator access required' using errcode='42501'; end if;
  if p_request_key is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_request_key::text,0));
    select * into v_existing from public.admin_notification_campaigns where request_key=p_request_key limit 1;
    if found then return jsonb_build_object('success',v_existing.status in ('completed','partial','queued','sending'),
      'campaign_id',v_existing.id,'status',v_existing.status,'target_count',v_existing.target_count,
      'sent_count',v_existing.sent_count,'failed_count',v_existing.failed_count,
      'channel_results',v_existing.channel_results,'duplicate_request',true); end if;
  end if;
  if p_audience not in ('all_customers','selected_customers','inactive_30d') then raise exception 'Invalid discount campaign audience' using errcode='22023'; end if;
  if coalesce(cardinality(p_channels),0)=0 or not (p_channels <@ array['banner','notification','sms']::text[]) then raise exception 'At least one valid delivery channel is required' using errcode='22023'; end if;
  select * into v_discount from public.discounts where id=p_discount_id;
  if not found or not v_discount.is_active then raise exception 'Active discount not found' using errcode='P0002'; end if;
  if p_audience='selected_customers' then
    if coalesce(cardinality(p_customer_ids),0)>0 then
      select coalesce(array_agg(p.id order by p.id),'{}'::uuid[]) into v_customer_ids from public.profiles p
      where p.id=any(p_customer_ids) and p.role='customer' and p.status='active';
      if cardinality(v_customer_ids)<>cardinality(p_customer_ids) then raise exception 'One or more selected customers are invalid or inactive' using errcode='22023'; end if;
    elsif v_discount.restricted_to_customers then
      select coalesce(array_agg(t.user_id order by t.user_id),'{}'::uuid[]) into v_customer_ids
      from public.discount_customer_targets t join public.profiles p on p.id=t.user_id
      where t.discount_id=p_discount_id and p.role='customer' and p.status='active';
    else raise exception 'Select at least one customer' using errcode='22023'; end if;
    if cardinality(v_customer_ids)=0 then raise exception 'This discount has no eligible target customers' using errcode='22023'; end if;
  elsif p_audience='inactive_30d' then
    select coalesce(array_agg(p.id order by p.id),'{}'::uuid[]) into v_customer_ids from public.profiles p
    where p.role='customer' and p.status='active' and not exists(
      select 1 from public.orders o where o.user_id=p.id and o.created_at>=pg_catalog.now()-interval '30 days' and o.status<>'cancelled');
    if cardinality(v_customer_ids)=0 then raise exception 'No eligible customers in this segment' using errcode='P0002'; end if;
  elsif v_discount.restricted_to_customers then
    select coalesce(array_agg(t.user_id order by t.user_id),'{}'::uuid[]) into v_customer_ids
    from public.discount_customer_targets t join public.profiles p on p.id=t.user_id
    where t.discount_id=p_discount_id and p.role='customer' and p.status='active';
    if cardinality(v_customer_ids)=0 then raise exception 'This discount has no eligible target customers' using errcode='22023'; end if;
    p_audience:='selected_customers';
  else
    select coalesce(array_agg(p.id order by p.id),'{}'::uuid[]) into v_customer_ids from public.profiles p where p.role='customer' and p.status='active';
  end if;
  if 'banner'=any(p_channels) and (p_audience<>'all_customers' or v_discount.restricted_to_customers) then raise exception 'A public banner cannot advertise a customer-restricted campaign' using errcode='22023'; end if;
  if p_audience in ('selected_customers','inactive_30d') and cardinality(p_customer_ids)>0 then
    delete from public.discount_customer_targets where discount_id=p_discount_id;
    insert into public.discount_customer_targets(discount_id,user_id,phone_snapshot) select p_discount_id,p.id,p.phone from public.profiles p where p.id=any(v_customer_ids);
    update public.discounts set restricted_to_customers=true,updated_at=pg_catalog.now() where id=p_discount_id;
  elsif p_audience='inactive_30d' then
    delete from public.discount_customer_targets where discount_id=p_discount_id;
    insert into public.discount_customer_targets(discount_id,user_id,phone_snapshot) select p_discount_id,p.id,p.phone from public.profiles p where p.id=any(v_customer_ids);
    update public.discounts set restricted_to_customers=true,updated_at=pg_catalog.now() where id=p_discount_id;
  end if;
  v_result:=public.admin_dispatch_discount_delivery(p_discount_id,p_channels,p_source_campaign_id);
  v_campaign_id:=nullif(v_result->>'campaign_id','')::uuid;
  if v_campaign_id is not null then
    update public.admin_notification_campaigns set request_key=p_request_key,
      audience=case p_audience when 'selected_customers' then 'targeted_discount' else p_audience end,
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('audience_mode',p_audience,
        'audience_count',cardinality(v_customer_ids),
        'customer_ids',case when p_audience='selected_customers' and cardinality(p_customer_ids)>0 then to_jsonb(v_customer_ids) else '[]'::jsonb end),
      updated_at=pg_catalog.now() where id=v_campaign_id;
  end if;
  return v_result||jsonb_build_object('audience',p_audience,'audience_count',cardinality(v_customer_ids));
end;
$function$;
