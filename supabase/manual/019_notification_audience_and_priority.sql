-- Notification audience and priority support.
-- Applied to the linked Supabase project as migration notification_audience_and_priority.

alter table public.admin_notifications
  add column if not exists priority text not null default 'normal'
    check (priority in ('normal','high','urgent')),
  add column if not exists audience text not null default 'admins'
    check (audience in ('admins','all_customers','inactive_30d'));

alter table public.customer_notifications
  add column if not exists priority text not null default 'normal'
    check (priority in ('normal','high','urgent')),
  add column if not exists audience text not null default 'all_customers'
    check (audience in ('all_customers','inactive_30d'));

create index if not exists idx_customer_notifications_user_created_priority
  on public.customer_notifications (user_id, created_at desc, priority);

create or replace function public.admin_send_notification(
  p_title text, p_body text, p_audience text, p_priority text default 'normal'
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_title text := pg_catalog.btrim(coalesce(p_title, ''));
  v_body text := pg_catalog.btrim(coalesce(p_body, ''));
  v_count integer := 0;
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

  return pg_catalog.jsonb_build_object('success',true,'recipient_count',v_count,
    'audience',p_audience,'priority',p_priority);
end;
$$;

revoke all on function public.admin_send_notification(text,text,text,text) from public,anon;
grant execute on function public.admin_send_notification(text,text,text,text) to authenticated;
