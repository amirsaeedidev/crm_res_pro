-- Transactional admin ticket reply: insert message and update ticket status atomically.
-- Run this in Supabase SQL Editor before using the CRM ticket reply action.

begin;

create or replace function public.admin_reply_to_ticket(
  p_ticket_id uuid,
  p_message text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_status text;
  v_message public.ticket_messages%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;

  if p_ticket_id is null then
    raise exception 'Ticket id is required' using errcode = '22023';
  end if;
  if p_message is null or pg_catalog.length(pg_catalog.btrim(p_message)) = 0 then
    raise exception 'Reply message cannot be empty' using errcode = '22023';
  end if;

  select t.status into v_status
    from public.tickets t
   where t.id = p_ticket_id
   for update;

  if not found then
    raise exception 'Ticket not found' using errcode = 'P0002';
  end if;
  if v_status = 'closed' then
    raise exception 'Ticket is closed; reopen it before replying' using errcode = '22023';
  end if;

  insert into public.ticket_messages (ticket_id, user_id, message, is_admin)
  values (p_ticket_id, v_user_id, pg_catalog.btrim(p_message), true)
  returning * into v_message;

  update public.tickets
     set status = 'answered', updated_at = pg_catalog.now()
   where id = p_ticket_id;

  return pg_catalog.to_jsonb(v_message);
end;
$function$;

revoke all on function public.admin_reply_to_ticket(uuid, text) from public;
revoke all on function public.admin_reply_to_ticket(uuid, text) from anon;
grant execute on function public.admin_reply_to_ticket(uuid, text) to authenticated;

commit;
