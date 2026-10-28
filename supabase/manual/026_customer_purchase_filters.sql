-- Customer CRM filters based on completed purchase history.
begin;
create index if not exists orders_customer_purchase_metrics_idx
  on public.orders (user_id, completed_at desc)
  include (total_amount, created_at)
  where status = 'completed';

create or replace function public.get_customer_purchase_metrics(
  p_search text default null,
  p_status_filter text default 'all',
  p_marketing_filter boolean default null,
  p_min_orders bigint default null,
  p_max_orders bigint default null,
  p_min_spend numeric default null,
  p_max_spend numeric default null,
  p_last_visit_since timestamptz default null,
  p_never_visited boolean default false,
  p_sort_by text default 'recent',
  p_page integer default 1,
  p_page_size integer default 20
)
returns json
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_result json;
begin
  if not (select public.is_admin()) then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if p_page < 1 or p_page_size < 1 or p_page_size > 100 then
    raise exception 'Invalid pagination' using errcode = '22023';
  end if;
  if p_min_orders is not null and p_max_orders is not null and p_min_orders > p_max_orders then
    raise exception 'Minimum purchase count cannot exceed maximum' using errcode = '22023';
  end if;
  if p_min_spend is not null and p_max_spend is not null and p_min_spend > p_max_spend then
    raise exception 'Minimum spend cannot exceed maximum' using errcode = '22023';
  end if;
  if coalesce(p_sort_by,'recent') not in ('recent','oldest_visit','count','spend') then
    raise exception 'Invalid sort option' using errcode = '22023';
  end if;

  with order_metrics as (
    select
      o.user_id,
      count(*)::bigint as purchase_count,
      coalesce(sum(o.total_amount), 0)::numeric as total_purchase_amount,
      max(coalesce(o.completed_at, o.created_at)) as last_purchase_at
    from public.orders o
    where o.status = 'completed'
    group by o.user_id
  ),
  customer_rows as (
    select
      p.id, p.email, p.first_name, p.last_name, p.phone, p.avatar_url,
      p.role, p.status, p.marketing_sms_opt_in, p.created_at,
      coalesce(m.purchase_count, 0)::bigint as purchase_count,
      coalesce(m.total_purchase_amount, 0)::numeric as total_purchase_amount,
      m.last_purchase_at
    from public.profiles p
    left join order_metrics m on m.user_id = p.id
    where p.role = 'customer'
      and (
        nullif(trim(coalesce(p_search,'')), '') is null
        or coalesce(p.first_name,'') ilike '%' || trim(p_search) || '%'
        or coalesce(p.last_name,'') ilike '%' || trim(p_search) || '%'
        or coalesce(p.email,'') ilike '%' || trim(p_search) || '%'
        or coalesce(p.phone,'') ilike '%' || trim(p_search) || '%'
      )
      and (coalesce(p_status_filter,'all') = 'all' or p.status = p_status_filter)
      and (p_marketing_filter is null or p.marketing_sms_opt_in = p_marketing_filter)
  ),
  filtered_rows as (
    select * from customer_rows c
    where (p_min_orders is null or c.purchase_count >= p_min_orders)
      and (p_max_orders is null or c.purchase_count <= p_max_orders)
      and (p_min_spend is null or c.total_purchase_amount >= p_min_spend)
      and (p_max_spend is null or c.total_purchase_amount <= p_max_spend)
      and (
        case
          when coalesce(p_never_visited,false) then c.last_purchase_at is null
          when p_last_visit_since is not null then c.last_purchase_at >= p_last_visit_since
          else true
        end
      )
  ),
  page_rows as (
    select * from filtered_rows c
    order by
      case when p_sort_by = 'spend' then c.total_purchase_amount end desc nulls last,
      case when p_sort_by = 'count' then c.purchase_count end desc nulls last,
      case when p_sort_by = 'oldest_visit' then c.last_purchase_at end asc nulls last,
      case when p_sort_by = 'recent' then c.last_purchase_at end desc nulls last,
      c.created_at desc
    limit p_page_size offset ((p_page - 1) * p_page_size)
  )
  select json_build_object(
    'total_count', (select count(*) from filtered_rows),
    'customers', coalesce((
      select json_agg(json_build_object(
        'id', id, 'email', email, 'first_name', first_name, 'last_name', last_name,
        'phone', phone, 'avatar_url', avatar_url, 'role', role, 'status', status,
        'marketing_sms_opt_in', marketing_sms_opt_in, 'created_at', created_at,
        'purchase_count', purchase_count, 'total_purchase_amount', total_purchase_amount,
        'last_purchase_at', last_purchase_at
      ))
      from page_rows
    ), '[]'::json)
  ) into v_result;
  return v_result;
end;
$$;

revoke all on function public.get_customer_purchase_metrics(text,text,boolean,bigint,bigint,numeric,numeric,timestamptz,boolean,text,integer,integer) from public, anon;
grant execute on function public.get_customer_purchase_metrics(text,text,boolean,bigint,bigint,numeric,numeric,timestamptz,boolean,text,integer,integer) to authenticated;
commit;
