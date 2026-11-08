-- Remove the product-level SMS consent model and standalone marketing campaigns.
-- Order-status SMS and discount-code SMS remain supported.

-- Keep historical discount campaign rows, but prevent old standalone marketing rows
-- from being dispatched after this migration.
UPDATE public.sms_outbox o
   SET event_key = 'discount_campaign', updated_at = pg_catalog.now()
  FROM public.sms_campaigns c
 WHERE o.campaign_id = c.id
   AND c.discount_id IS NOT NULL
   AND o.event_key = 'marketing_campaign';

UPDATE public.sms_outbox o
   SET status = 'cancelled',
       last_error = 'لغو شد: کمپین مستقل پیامکی از محصول حذف شده است.',
       updated_at = pg_catalog.now()
 WHERE o.status IN ('queued','retry')
   AND o.event_key = 'marketing_campaign'
   AND NOT EXISTS (
     SELECT 1 FROM public.sms_campaigns c
      WHERE c.id = o.campaign_id AND c.discount_id IS NOT NULL
   );

-- The SMS Center no longer creates standalone campaigns. Discount dispatch still
-- calls the discount-linked 10-argument overload below.
DROP FUNCTION IF EXISTS public.admin_create_sms_campaign(
  text, uuid[], text, text, text[], jsonb
);
DROP FUNCTION IF EXISTS public.admin_create_sms_campaign_scheduled(
  text, uuid[], text, text, text[], jsonb, uuid, numeric, numeric, integer, timestamptz
);

CREATE OR REPLACE FUNCTION public.admin_create_sms_campaign(
  p_name text,
  p_customer_ids uuid[],
  p_normal_message text,
  p_pattern_body_id text DEFAULT NULL,
  p_pattern_args text[] DEFAULT '{}'::text[],
  p_audience_filter jsonb DEFAULT '{}'::jsonb,
  p_discount_id uuid DEFAULT NULL,
  p_sms_cost_per_message numeric DEFAULT 0,
  p_other_campaign_cost numeric DEFAULT 0,
  p_attribution_window_days integer DEFAULT 7
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_settings public.sms_settings%rowtype;
  v_discount public.discounts%rowtype;
  v_campaign_id uuid;
  v_count integer := 0;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Administrator access required' USING errcode = '42501';
  END IF;

  IF p_discount_id IS NULL THEN
    RAISE EXCEPTION 'SMS campaigns must be linked to a discount' USING errcode = '22023';
  END IF;

  SELECT * INTO v_settings FROM public.sms_settings WHERE id = 1;
  IF NOT FOUND OR NOT v_settings.sms_enabled THEN
    RAISE EXCEPTION 'SMS sending is disabled in settings' USING errcode = '22023';
  END IF;

  SELECT * INTO v_discount
    FROM public.discounts
   WHERE id = p_discount_id AND is_active = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Selected discount is not active' USING errcode = '22023';
  END IF;

  IF COALESCE(pg_catalog.cardinality(p_customer_ids), 0) = 0 THEN
    RAISE EXCEPTION 'At least one customer must be selected' USING errcode = '22023';
  END IF;

  IF v_settings.send_mode = 'normal'
     AND pg_catalog.length(pg_catalog.btrim(COALESCE(p_normal_message, ''))) = 0 THEN
    RAISE EXCEPTION 'SMS message cannot be empty' USING errcode = '22023';
  END IF;

  IF v_settings.send_mode = 'pattern'
     AND pg_catalog.length(pg_catalog.btrim(COALESCE(p_pattern_body_id, v_settings.default_body_id, ''))) = 0 THEN
    RAISE EXCEPTION 'Pattern Body ID is required' USING errcode = '22023';
  END IF;

  IF v_discount.restricted_to_customers AND EXISTS (
    SELECT 1
      FROM public.profiles p
     WHERE p.id = ANY(p_customer_ids)
       AND p.role = 'customer'
       AND p.status = 'active'
       AND NOT EXISTS (
         SELECT 1 FROM public.discount_customer_targets t
          WHERE t.discount_id = p_discount_id AND t.user_id = p.id
       )
  ) THEN
    RAISE EXCEPTION 'The selected restricted discount is not assigned to every campaign recipient'
      USING errcode = '22023';
  END IF;

  IF COALESCE(p_sms_cost_per_message, 0) < 0
     OR COALESCE(p_other_campaign_cost, 0) < 0 THEN
    RAISE EXCEPTION 'Campaign costs cannot be negative' USING errcode = '22023';
  END IF;

  IF COALESCE(p_attribution_window_days, 7) NOT BETWEEN 1 AND 90 THEN
    RAISE EXCEPTION 'Attribution window must be between 1 and 90 days' USING errcode = '22023';
  END IF;

  INSERT INTO public.sms_campaigns(
    name, send_mode, normal_message, pattern_body_id, pattern_args,
    audience_filter, status, created_by, discount_id,
    sms_cost_per_message, other_campaign_cost, attribution_window_days
  )
  VALUES (
    COALESCE(NULLIF(pg_catalog.btrim(p_name), ''), 'ارسال کد تخفیف'),
    v_settings.send_mode,
    COALESCE(p_normal_message, ''),
    COALESCE(NULLIF(pg_catalog.btrim(p_pattern_body_id), ''), v_settings.default_body_id),
    COALESCE(p_pattern_args, '{}'::text[]),
    COALESCE(p_audience_filter, '{}'::jsonb),
    'queued',
    (SELECT auth.uid()),
    p_discount_id,
    GREATEST(COALESCE(p_sms_cost_per_message, 0), 0),
    GREATEST(COALESCE(p_other_campaign_cost, 0), 0),
    COALESCE(p_attribution_window_days, 7)
  )
  RETURNING id INTO v_campaign_id;

  INSERT INTO public.sms_outbox(
    event_key, recipient_user_id, recipient_phone, send_mode,
    normal_message, pattern_body_id, pattern_args, status,
    attempts, max_attempts, campaign_id, idempotency_key
  )
  SELECT
    'discount_campaign',
    p.id,
    pg_catalog.btrim(p.phone),
    v_settings.send_mode,
    COALESCE(p_normal_message, ''),
    COALESCE(NULLIF(pg_catalog.btrim(p_pattern_body_id), ''), v_settings.default_body_id),
    ARRAY(
      SELECT pg_catalog.replace(
        pg_catalog.replace(
          arg,
          '{{name}}',
          COALESCE(NULLIF(pg_catalog.btrim(COALESCE(p.first_name, '') || ' ' || COALESCE(p.last_name, '')), ''), 'مشتری')
        ),
        '{{phone}}',
        p.phone
      )
      FROM pg_catalog.unnest(COALESCE(p_pattern_args, '{}'::text[])) AS arg
    ),
    'queued',
    0,
    v_settings.max_attempts,
    v_campaign_id,
    v_campaign_id::text || ':' || p.id::text
  FROM public.profiles p
  WHERE p.id = ANY(p_customer_ids)
    AND p.role = 'customer'
    AND p.status = 'active'
    AND NULLIF(pg_catalog.btrim(COALESCE(p.phone, '')), '') IS NOT NULL
  ON CONFLICT (idempotency_key) DO NOTHING;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count = 0 THEN
    RAISE EXCEPTION 'No selected customers have a usable phone number' USING errcode = '22023';
  END IF;

  UPDATE public.sms_campaigns SET recipient_count = v_count WHERE id = v_campaign_id;

  RETURN pg_catalog.jsonb_build_object(
    'campaign_id', v_campaign_id,
    'recipient_count', v_count,
    'status', 'queued'
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_create_sms_campaign(
  text, uuid[], text, text, text[], jsonb, uuid, numeric, numeric, integer
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_create_sms_campaign(
  text, uuid[], text, text, text[], jsonb, uuid, numeric, numeric, integer
) TO authenticated;

-- Claim only operational events and discount-linked SMS. No consent field is
-- consulted; generic marketing_campaign rows are never sent.
CREATE OR REPLACE FUNCTION public.sms_claim_pending_batch(p_limit integer DEFAULT 20)
RETURNS SETOF public.sms_outbox
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  UPDATE public.sms_campaigns c
     SET status = 'cancelled',
         cancelled_at = COALESCE(c.cancelled_at, pg_catalog.now()),
         completed_at = pg_catalog.now()
   WHERE c.status IN ('queued','sending')
     AND c.discount_id IS NULL
     AND NOT EXISTS (
       SELECT 1 FROM public.sms_outbox o
        WHERE o.campaign_id = c.id AND o.status IN ('queued','retry','sending')
     );

  RETURN QUERY
  WITH picked AS (
    SELECT o.id
      FROM public.sms_outbox o
      LEFT JOIN public.sms_campaigns c ON c.id = o.campaign_id
     WHERE o.status IN ('queued','retry')
       AND o.next_attempt_at <= pg_catalog.now()
       AND (
         o.campaign_id IS NULL
         OR (c.status IN ('queued','sending') AND c.scheduled_at <= pg_catalog.now())
       )
       AND (
         o.event_key <> 'discount_campaign'
         OR (c.id IS NOT NULL AND c.discount_id IS NOT NULL)
       )
       AND o.event_key <> 'marketing_campaign'
     ORDER BY o.next_attempt_at, o.created_at
     FOR UPDATE OF o SKIP LOCKED
     LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 20), 100))
  ),
  updated AS (
    UPDATE public.sms_outbox o
       SET status = 'sending',
           attempts = o.attempts + 1,
           updated_at = pg_catalog.now()
      FROM picked
     WHERE o.id = picked.id
    RETURNING o.*
  )
  SELECT * FROM updated ORDER BY created_at;
END;
$function$;

-- Remove the consent-dependent customer RPC and replace it with the same
-- customer metrics contract without any marketing-consent parameter or field.
DROP FUNCTION IF EXISTS public.get_customer_purchase_metrics(
  text, text, boolean, bigint, bigint, numeric, numeric, timestamptz,
  boolean, text, integer, integer, text
);

CREATE OR REPLACE FUNCTION public.get_customer_purchase_metrics(
  p_search text DEFAULT NULL,
  p_status_filter text DEFAULT 'all',
  p_min_orders bigint DEFAULT NULL,
  p_max_orders bigint DEFAULT NULL,
  p_min_spend numeric DEFAULT NULL,
  p_max_spend numeric DEFAULT NULL,
  p_last_visit_since timestamptz DEFAULT NULL,
  p_never_visited boolean DEFAULT false,
  p_sort_by text DEFAULT 'recent',
  p_page integer DEFAULT 1,
  p_page_size integer DEFAULT 20,
  p_segment text DEFAULT 'all'
)
RETURNS json
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
  v_result json;
BEGIN
  IF NOT (SELECT public.is_admin()) THEN
    RAISE EXCEPTION 'Administrator access required' USING errcode = '42501';
  END IF;
  IF p_page < 1 OR p_page_size < 1 OR p_page_size > 100 THEN
    RAISE EXCEPTION 'Invalid pagination' USING errcode = '22023';
  END IF;
  IF p_min_orders IS NOT NULL AND p_max_orders IS NOT NULL AND p_min_orders > p_max_orders THEN
    RAISE EXCEPTION 'Minimum purchase count cannot exceed maximum' USING errcode = '22023';
  END IF;
  IF p_min_spend IS NOT NULL AND p_max_spend IS NOT NULL AND p_min_spend > p_max_spend THEN
    RAISE EXCEPTION 'Minimum spend cannot exceed maximum' USING errcode = '22023';
  END IF;
  IF COALESCE(p_segment, 'all') NOT IN ('all','loyal','inactive','new') THEN
    RAISE EXCEPTION 'Invalid customer segment' USING errcode = '22023';
  END IF;
  IF COALESCE(p_sort_by, 'recent') NOT IN ('recent','oldest_visit','count','spend') THEN
    RAISE EXCEPTION 'Invalid sort option' USING errcode = '22023';
  END IF;

  WITH order_metrics AS (
    SELECT
      o.user_id,
      pg_catalog.count(*)::bigint AS purchase_count,
      COALESCE(pg_catalog.sum(o.total_amount), 0)::numeric AS total_purchase_amount,
      pg_catalog.max(COALESCE(o.completed_at, o.created_at)) AS last_purchase_at
    FROM public.orders o
    WHERE o.status = 'completed'
    GROUP BY o.user_id
  ),
  customer_rows AS (
    SELECT
      p.id, p.email, p.first_name, p.last_name, p.phone, p.avatar_url,
      p.role, p.status, p.created_at,
      COALESCE(m.purchase_count, 0)::bigint AS purchase_count,
      COALESCE(m.total_purchase_amount, 0)::numeric AS total_purchase_amount,
      m.last_purchase_at
    FROM public.profiles p
    LEFT JOIN order_metrics m ON m.user_id = p.id
    WHERE p.role = 'customer'
      AND (
        NULLIF(pg_catalog.btrim(COALESCE(p_search, '')), '') IS NULL
        OR COALESCE(p.first_name, '') ILIKE '%' || pg_catalog.btrim(p_search) || '%'
        OR COALESCE(p.last_name, '') ILIKE '%' || pg_catalog.btrim(p_search) || '%'
        OR COALESCE(p.email, '') ILIKE '%' || pg_catalog.btrim(p_search) || '%'
        OR COALESCE(p.phone, '') ILIKE '%' || pg_catalog.btrim(p_search) || '%'
      )
      AND (COALESCE(p_status_filter, 'all') = 'all' OR p.status = p_status_filter)
  ),
  filtered_rows AS (
    SELECT * FROM customer_rows c
    WHERE (p_min_orders IS NULL OR c.purchase_count >= p_min_orders)
      AND (p_max_orders IS NULL OR c.purchase_count <= p_max_orders)
      AND (p_min_spend IS NULL OR c.total_purchase_amount >= p_min_spend)
      AND (p_max_spend IS NULL OR c.total_purchase_amount <= p_max_spend)
      AND (
        COALESCE(p_segment, 'all') = 'all'
        OR (p_segment = 'loyal' AND c.purchase_count >= 5 AND c.last_purchase_at >= pg_catalog.now() - interval '60 days')
        OR (p_segment = 'inactive' AND (
          c.last_purchase_at < pg_catalog.now() - interval '90 days'
          OR (c.last_purchase_at IS NULL AND c.created_at < pg_catalog.now() - interval '30 days')
        ))
        OR (p_segment = 'new' AND c.created_at >= pg_catalog.now() - interval '30 days')
      )
      AND (
        CASE
          WHEN COALESCE(p_never_visited, false) THEN c.last_purchase_at IS NULL
          WHEN p_last_visit_since IS NOT NULL THEN c.last_purchase_at >= p_last_visit_since
          ELSE true
        END
      )
  ),
  page_rows AS (
    SELECT * FROM filtered_rows c
    ORDER BY
      CASE WHEN p_sort_by = 'spend' THEN c.total_purchase_amount END DESC NULLS LAST,
      CASE WHEN p_sort_by = 'count' THEN c.purchase_count END DESC NULLS LAST,
      CASE WHEN p_sort_by = 'oldest_visit' THEN c.last_purchase_at END ASC NULLS LAST,
      CASE WHEN p_sort_by = 'recent' THEN c.last_purchase_at END DESC NULLS LAST,
      c.created_at DESC
    LIMIT p_page_size OFFSET ((p_page - 1) * p_page_size)
  )
  SELECT pg_catalog.json_build_object(
    'total_count', (SELECT pg_catalog.count(*) FROM filtered_rows),
    'customers', COALESCE((
      SELECT pg_catalog.json_agg(pg_catalog.json_build_object(
        'id', id, 'email', email, 'first_name', first_name, 'last_name', last_name,
        'phone', phone, 'avatar_url', avatar_url, 'role', role, 'status', status,
        'created_at', created_at, 'purchase_count', purchase_count,
        'total_purchase_amount', total_purchase_amount, 'last_purchase_at', last_purchase_at
      ))
      FROM page_rows
    ), '[]'::json)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_customer_purchase_metrics(
  text, text, bigint, bigint, numeric, numeric, timestamptz, boolean, text, integer, integer, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_customer_purchase_metrics(
  text, text, bigint, bigint, numeric, numeric, timestamptz, boolean, text, integer, integer, text
) TO authenticated;

-- Remove the obsolete customer-facing consent mutation endpoint.
DROP FUNCTION IF EXISTS public.customer_set_marketing_sms_opt_in(boolean);

-- Update the audit restore allow-list before dropping the legacy fields.
CREATE OR REPLACE FUNCTION public.admin_restore_activity_log(p_log_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_log public.admin_activity_logs%ROWTYPE;
  v_columns text;
  v_rows integer;
  v_table text;
BEGIN
  IF auth.uid() IS NULL OR NOT COALESCE(public.is_admin(), false) THEN
    RAISE EXCEPTION 'admin access required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_log FROM public.admin_activity_logs WHERE id = p_log_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'activity log not found'; END IF;
  IF v_log.action <> 'UPDATE' OR v_log.old_data IS NULL OR v_log.record_id IS NULL THEN
    RAISE EXCEPTION 'only supported update entries can be restored';
  END IF;

  v_table := v_log.table_name;
  IF v_table NOT IN ('products','categories','banners','discounts','profiles') THEN
    RAISE EXCEPTION 'restore is not supported for this table';
  END IF;

  SELECT pg_catalog.string_agg(pg_catalog.format('%I', a.attname), ', ' ORDER BY a.attnum)
    INTO v_columns
  FROM pg_catalog.pg_attribute a
  WHERE a.attrelid = pg_catalog.to_regclass('public.' || v_table)
    AND a.attnum > 0
    AND NOT a.attisdropped
    AND a.attname NOT IN ('id','created_at','updated_at','email','role')
    AND a.attgenerated = ''
    AND v_log.old_data ? a.attname
    AND (
      v_table <> 'profiles'
      OR a.attname IN ('first_name','last_name','phone','avatar_url','status')
    );

  IF v_columns IS NULL OR v_columns = '' THEN
    RAISE EXCEPTION 'no restorable columns found';
  END IF;

  PERFORM pg_catalog.set_config('app.crm_audit_action', 'RESTORE', true);
  PERFORM pg_catalog.set_config('app.crm_audit_source', p_log_id::text, true);

  EXECUTE pg_catalog.format(
    'UPDATE public.%I AS target SET (%s) = (SELECT %s FROM pg_catalog.jsonb_populate_record(NULL::public.%I, $1)) WHERE target.id::text = $2',
    v_table, v_columns, v_columns, v_table
  ) USING v_log.old_data, v_log.record_id;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RAISE EXCEPTION 'record no longer exists; it cannot be restored';
  END IF;

  RETURN p_log_id;
END;
$function$;

-- Keep the existing CRM views and customer data contract, without consent fields.
DROP VIEW IF EXISTS public.customer_crm_view;
DROP VIEW IF EXISTS public.customer_directory_view;

CREATE VIEW public.customer_crm_view
WITH (security_invoker = true) AS
SELECT
  p.id, p.email, p.first_name, p.last_name, p.phone, p.avatar_url, p.role, p.status,
  p.created_at,
  COALESCE(s.total_order_count, 0::bigint) AS total_order_count,
  COALESCE(s.completed_order_count, 0::bigint) AS completed_order_count,
  COALESCE(s.open_order_count, 0::bigint) AS open_order_count,
  COALESCE(s.total_spent, 0::numeric) AS total_spent,
  s.last_order_at,
  s.last_order_id,
  COALESCE(w.balance, 0::numeric) AS wallet_balance
FROM public.profiles p
LEFT JOIN (
  SELECT
    o.user_id,
    pg_catalog.count(*) AS total_order_count,
    pg_catalog.count(*) FILTER (WHERE o.status = 'completed'::text) AS completed_order_count,
    pg_catalog.count(*) FILTER (WHERE o.status <> ALL (ARRAY['completed'::text,'cancelled'::text])) AS open_order_count,
    COALESCE(pg_catalog.sum(o.total_amount) FILTER (WHERE o.status = 'completed'::text), 0::numeric) AS total_spent,
    pg_catalog.max(o.created_at) AS last_order_at,
    (pg_catalog.array_agg(o.id ORDER BY o.created_at DESC))[1] AS last_order_id
  FROM public.orders o
  GROUP BY o.user_id
) s ON s.user_id = p.id
LEFT JOIN public.customer_wallets w ON w.user_id = p.id
WHERE p.role = 'customer';

CREATE VIEW public.customer_directory_view
WITH (security_invoker = true) AS
SELECT
  p.id, p.email, p.first_name, p.last_name, p.phone, p.avatar_url, p.role, p.status,
  p.created_at,
  COALESCE(o.total_orders, 0::bigint) AS total_orders,
  COALESCE(o.completed_orders, 0::bigint) AS completed_orders,
  COALESCE(o.incomplete_orders, 0::bigint) AS incomplete_orders,
  COALESCE(o.lifetime_spend, 0::numeric) AS lifetime_spend,
  o.last_order_at,
  COALESCE(w.balance, 0::numeric) AS wallet_balance
FROM public.profiles p
LEFT JOIN LATERAL (
  SELECT
    pg_catalog.count(*) FILTER (WHERE ord.status <> 'cancelled'::text) AS total_orders,
    pg_catalog.count(*) FILTER (WHERE ord.status = 'completed'::text) AS completed_orders,
    pg_catalog.count(*) FILTER (WHERE ord.status = ANY (ARRAY['pending'::text,'confirmed'::text,'preparing'::text,'ready'::text,'out_for_delivery'::text])) AS incomplete_orders,
    COALESCE(pg_catalog.sum(ord.total_amount) FILTER (WHERE ord.status = 'completed'::text), 0::numeric) AS lifetime_spend,
    pg_catalog.max(ord.created_at) AS last_order_at
  FROM public.orders ord
  WHERE ord.user_id = p.id
) o ON true
LEFT JOIN public.customer_wallets w ON w.user_id = p.id
WHERE p.role = 'customer';

GRANT SELECT ON public.customer_crm_view, public.customer_directory_view TO authenticated;

-- Drop the obsolete product consent model and global marketing switch.
ALTER TABLE public.profiles
  DROP COLUMN IF EXISTS marketing_sms_opt_in,
  DROP COLUMN IF EXISTS marketing_sms_opt_in_at;

ALTER TABLE public.sms_settings
  DROP COLUMN IF EXISTS marketing_enabled;

-- Save only operational SMS configuration. Discount-code SMS is controlled by
-- the discount campaign channel selector and the master sms_enabled switch.
DROP FUNCTION IF EXISTS public.admin_save_sms_settings(
  boolean, boolean, text, text, text, text, text, text,
  boolean, boolean, boolean, boolean, integer, integer
);

CREATE OR REPLACE FUNCTION public.admin_save_sms_settings(
  p_sms_enabled boolean,
  p_send_mode text,
  p_username text,
  p_api_key text,
  p_sender_number text,
  p_default_body_id text,
  p_admin_notification_phone text,
  p_notify_order_ready_customer boolean,
  p_notify_ticket_customer boolean,
  p_notify_ticket_admin boolean,
  p_notify_new_orders_staff boolean,
  p_max_attempts integer,
  p_retry_delay_seconds integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_secret_id uuid;
  v_key_present boolean := false;
  v_settings jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Administrator access required' USING errcode = '42501';
  END IF;
  IF p_send_mode NOT IN ('normal','pattern') THEN
    RAISE EXCEPTION 'Invalid SMS mode' USING errcode = '22023';
  END IF;
  IF p_max_attempts NOT BETWEEN 1 AND 10 THEN
    RAISE EXCEPTION 'Max attempts must be between 1 and 10' USING errcode = '22023';
  END IF;
  IF p_retry_delay_seconds NOT BETWEEN 5 AND 86400 THEN
    RAISE EXCEPTION 'Retry delay must be between 5 and 86400 seconds' USING errcode = '22023';
  END IF;

  INSERT INTO public.sms_settings(
    id, sms_enabled, send_mode, username, sender_number, default_body_id,
    admin_notification_phone, notify_order_ready_customer, notify_ticket_customer,
    notify_ticket_admin, notify_new_orders_staff, max_attempts,
    retry_delay_seconds, updated_by, updated_at
  ) VALUES (
    1, COALESCE(p_sms_enabled,false), p_send_mode, COALESCE(pg_catalog.btrim(p_username),''),
    COALESCE(pg_catalog.btrim(p_sender_number),''), COALESCE(pg_catalog.btrim(p_default_body_id),''),
    COALESCE(pg_catalog.btrim(p_admin_notification_phone),''), COALESCE(p_notify_order_ready_customer,true),
    COALESCE(p_notify_ticket_customer,true), COALESCE(p_notify_ticket_admin,true),
    COALESCE(p_notify_new_orders_staff,true), p_max_attempts, p_retry_delay_seconds,
    (SELECT auth.uid()), pg_catalog.now()
  )
  ON CONFLICT (id) DO UPDATE SET
    sms_enabled = EXCLUDED.sms_enabled,
    send_mode = EXCLUDED.send_mode,
    username = EXCLUDED.username,
    sender_number = EXCLUDED.sender_number,
    default_body_id = EXCLUDED.default_body_id,
    admin_notification_phone = EXCLUDED.admin_notification_phone,
    notify_order_ready_customer = EXCLUDED.notify_order_ready_customer,
    notify_ticket_customer = EXCLUDED.notify_ticket_customer,
    notify_ticket_admin = EXCLUDED.notify_ticket_admin,
    notify_new_orders_staff = EXCLUDED.notify_new_orders_staff,
    max_attempts = EXCLUDED.max_attempts,
    retry_delay_seconds = EXCLUDED.retry_delay_seconds,
    updated_by = EXCLUDED.updated_by,
    updated_at = pg_catalog.now();

  IF NULLIF(pg_catalog.btrim(COALESCE(p_api_key,'')),'') IS NOT NULL THEN
    SELECT id INTO v_secret_id
      FROM vault.decrypted_secrets
     WHERE name = 'melipayamak_api_key'
     LIMIT 1;
    IF v_secret_id IS NULL THEN
      PERFORM vault.create_secret(pg_catalog.btrim(p_api_key),'melipayamak_api_key','Melipayamak SMS API key',NULL);
    ELSE
      PERFORM vault.update_secret(v_secret_id,pg_catalog.btrim(p_api_key),'melipayamak_api_key','Melipayamak SMS API key',NULL);
    END IF;
  END IF;

  SELECT EXISTS(SELECT 1 FROM vault.decrypted_secrets WHERE name='melipayamak_api_key')
    INTO v_key_present;
  UPDATE public.sms_settings SET provider_key_configured=v_key_present,updated_at=pg_catalog.now() WHERE id=1;
  SELECT pg_catalog.to_jsonb(s) - 'updated_by' INTO v_settings FROM public.sms_settings s WHERE id=1;
  RETURN pg_catalog.jsonb_build_object('saved',true,'api_key_configured',v_key_present,'settings',v_settings);
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_save_sms_settings(
  boolean, text, text, text, text, text, text, boolean, boolean, boolean, boolean, integer, integer
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_save_sms_settings(
  boolean, text, text, text, text, text, text, boolean, boolean, boolean, boolean, integer, integer
) TO authenticated;
