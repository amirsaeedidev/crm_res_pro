-- Fix admin activity audit trigger: include the operation value in the insert.
-- The original 035 migration listed four columns but supplied only three values,
-- which caused writes to audited tables to fail when the trigger fired.

create or replace function public.capture_admin_activity_log()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_data jsonb;
  row_id text;
begin
  if tg_op = 'DELETE' then
    row_data := to_jsonb(old);
  else
    row_data := to_jsonb(new);
  end if;

  row_id := coalesce(
    row_data ->> 'id',
    row_data ->> 'uuid',
    row_data ->> 'table_id'
  );

  insert into public.admin_activity_logs (
    table_name,
    record_id,
    operation,
    actor_id
  )
  values (
    tg_table_name,
    row_id,
    tg_op,
    auth.uid()
  );

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

revoke all on function public.capture_admin_activity_log() from public, anon, authenticated;
