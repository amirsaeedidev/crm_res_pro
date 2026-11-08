begin;

create or replace function public.guard_reservation_status_transition()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  v_allowed boolean := false;
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  v_allowed := case old.status
    when 'pending' then new.status in ('confirmed', 'cancelled', 'no_show')
    when 'confirmed' then new.status in ('delayed', 'arrived', 'cancelled', 'no_show')
    when 'delayed' then new.status in ('confirmed', 'arrived', 'cancelled', 'no_show')
    when 'arrived' then new.status in ('completed', 'cancelled')
    else false
  end;

  if not v_allowed then
    raise exception 'تغییر وضعیت رزرو از % به % مجاز نیست.', old.status, new.status
      using errcode = '23514';
  end if;

  return new;
end;
$function$;

drop trigger if exists reservations_guard_status_transition on public.reservations;
create trigger reservations_guard_status_transition
before update of status on public.reservations
for each row execute function public.guard_reservation_status_transition();

revoke all on function public.guard_reservation_status_transition() from public, anon, authenticated;

commit;