create or replace function public.reconcile_discount_campaign_sms_link()
returns trigger language plpgsql security definer set search_path=''
as $function$
declare
  v_sms public.sms_campaigns%rowtype;
  v_results jsonb;
  v_sent integer:=0;
  v_failed integer:=0;
  v_status text;
begin
  if new.sms_campaign_id is null or new.campaign_type<>'discount' then return new; end if;
  select * into v_sms from public.sms_campaigns where id=new.sms_campaign_id;
  if not found then return new; end if;
  v_results:=coalesce(new.channel_results,'{}'::jsonb);
  if v_sms.status in ('draft','queued') then
    v_status:='queued';
    v_results:=jsonb_set(v_results,'{sms}',coalesce(v_results->'sms','{}'::jsonb)||
      jsonb_build_object('status','queued','recipient_count',coalesce(v_sms.recipient_count,0)),true);
    v_sent:=coalesce((v_results->'notification'->>'recipient_count')::integer,0)
      +case when v_results->'banner'->>'status'='completed' then 1 else 0 end;
    v_failed:=case when v_results->'notification'->>'status'='failed' then 1 else 0 end
      +case when v_results->'banner'->>'status'='failed' then 1 else 0 end;
  else
    v_results:=jsonb_set(v_results,'{sms}',coalesce(v_results->'sms','{}'::jsonb)||
      jsonb_build_object('status',case when v_sms.status='completed' and coalesce(v_sms.failed_count,0)>0 then 'partial' else v_sms.status end,
        'sent_count',coalesce(v_sms.sent_count,0),'failed_count',coalesce(v_sms.failed_count,0),
        'delivered_count',coalesce(v_sms.delivered_count,0)),true);
    v_sent:=coalesce((v_results->'notification'->>'recipient_count')::integer,0)
      +case when v_results->'banner'->>'status'='completed' then 1 else 0 end
      +coalesce(v_sms.sent_count,0);
    v_failed:=case when v_results->'notification'->>'status'='failed' then 1 else 0 end
      +case when v_results->'banner'->>'status'='failed' then 1 else 0 end
      +coalesce(v_sms.failed_count,0);
    v_status:=case when v_failed>0 and v_sent>0 then 'partial'
      when v_failed>0 then 'failed' when v_sms.status='sending' then 'sending' else 'completed' end;
  end if;
  update public.admin_notification_campaigns set status=v_status,channel_results=v_results,
    sent_count=v_sent,failed_count=v_failed,updated_at=pg_catalog.now() where id=new.id;
  return new;
end;
$function$;
drop trigger if exists reconcile_discount_campaign_sms_link on public.admin_notification_campaigns;
create trigger reconcile_discount_campaign_sms_link after update of sms_campaign_id
on public.admin_notification_campaigns for each row execute function public.reconcile_discount_campaign_sms_link();
