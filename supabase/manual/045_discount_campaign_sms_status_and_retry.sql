-- Keep unified discount campaign status synchronized with the SMS worker and retry only failed SMS rows.
create or replace function public.sync_discount_campaign_sms_result()
returns trigger language plpgsql security definer set search_path = ''
as $function$
declare
  v_campaign public.admin_notification_campaigns%rowtype;
  v_results jsonb;
  v_notification_sent integer := 0;
  v_notification_failed integer := 0;
  v_banner_sent integer := 0;
  v_banner_failed integer := 0;
  v_total_sent integer := 0;
  v_total_failed integer := 0;
  v_status text;
  v_sms_status text;
begin
  select * into v_campaign from public.admin_notification_campaigns
  where sms_campaign_id=new.id order by created_at desc limit 1;
  if not found then return new; end if;
  v_results := coalesce(v_campaign.channel_results,'{}'::jsonb);
  v_sms_status := case
    when new.status='completed' and coalesce(new.failed_count,0)>0 then 'partial'
    when new.status='completed' then 'completed'
    when new.status='failed' then 'failed'
    when new.status='sending' then 'sending'
    when new.status='cancelled' then 'cancelled'
    else 'queued' end;
  v_results := jsonb_set(v_results,'{sms}',
    coalesce(v_results->'sms','{}'::jsonb) ||
      jsonb_build_object('status',v_sms_status,'sent_count',coalesce(new.sent_count,0),
        'failed_count',coalesce(new.failed_count,0),'delivered_count',coalesce(new.delivered_count,0)),true);
  v_notification_sent := coalesce((v_results->'notification'->>'recipient_count')::integer,0);
  if coalesce(v_results->'notification'->>'status','')='failed' then v_notification_failed:=1; end if;
  if coalesce(v_results->'banner'->>'status','')='completed' then v_banner_sent:=1; end if;
  if coalesce(v_results->'banner'->>'status','')='failed' then v_banner_failed:=1; end if;
  v_total_sent := v_notification_sent+v_banner_sent+coalesce(new.sent_count,0);
  v_total_failed := v_notification_failed+v_banner_failed+coalesce(new.failed_count,0);
  v_status := case when new.status in ('draft','queued') then 'queued'
    when new.status='sending' then 'sending'
    when v_total_failed>0 and v_total_sent>0 then 'partial'
    when v_total_failed>0 then 'failed' else 'completed' end;
  update public.admin_notification_campaigns
  set channel_results=v_results,sent_count=v_total_sent,failed_count=v_total_failed,
      status=v_status,updated_at=pg_catalog.now(),
      sent_at=case when v_total_sent>0 then coalesce(sent_at,pg_catalog.now()) else sent_at end
  where id=v_campaign.id;
  return new;
end;
$function$;

drop trigger if exists sync_discount_campaign_sms_result on public.sms_campaigns;
create trigger sync_discount_campaign_sms_result
after update of status,sent_count,failed_count,delivered_count on public.sms_campaigns
for each row execute function public.sync_discount_campaign_sms_result();

create or replace function public.admin_retry_sms_campaign_failures(p_campaign_id uuid)
returns jsonb language plpgsql security invoker set search_path = ''
as $function$
declare v_requeued integer:=0;
begin
  if auth.uid() is null or not coalesce((select public.is_admin()),false) then
    raise exception 'Administrator access required' using errcode='42501';
  end if;
  if not exists(select 1 from public.sms_campaigns where id=p_campaign_id) then
    raise exception 'SMS campaign not found' using errcode='P0002';
  end if;
  update public.sms_outbox set status='retry',attempts=0,
    max_attempts=greatest(coalesce(max_attempts,3),3),
    next_attempt_at=pg_catalog.now(),last_error=null,updated_at=pg_catalog.now()
  where campaign_id=p_campaign_id and status in ('failed','dead','error');
  get diagnostics v_requeued=row_count;
  if v_requeued=0 then
    raise exception 'No failed SMS messages are available to retry' using errcode='P0002';
  end if;
  update public.sms_campaigns set status='queued',failed_count=0,completed_at=null
  where id=p_campaign_id;
  return jsonb_build_object('success',true,'requeued_count',v_requeued,'campaign_id',p_campaign_id);
end;
$function$;

revoke all on function public.admin_retry_sms_campaign_failures(uuid) from public,anon;
grant execute on function public.admin_retry_sms_campaign_failures(uuid) to authenticated;
