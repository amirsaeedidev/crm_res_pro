-- Phase 10/11: dashboard data contract and server-side aggregate.
-- No new tables are introduced. Existing order/customer/catalog/discount/wallet data is reused.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS payment_mode text NOT NULL DEFAULT 'mock';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.orders'::regclass
      AND conname = 'orders_payment_mode_check'
  ) THEN
    ALTER TABLE public.orders
      ADD CONSTRAINT orders_payment_mode_check
      CHECK (payment_mode IN ('mock', 'real'));
  END IF;
END
$$;

COMMENT ON COLUMN public.orders.payment_mode IS
  'Payment processing mode: mock for the current simulated customer checkout; real only after a trusted payment confirmation.';

CREATE INDEX IF NOT EXISTS orders_dashboard_filter_idx
  ON public.orders (created_at, order_source, payment_mode, status);

CREATE OR REPLACE FUNCTION public.get_crm_dashboard_overview(
  p_start_at timestamptz DEFAULT NULL,
  p_end_at timestamptz DEFAULT NULL,
  p_order_source text DEFAULT 'all',
  p_payment_mode text DEFAULT 'all'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_now timestamptz := pg_catalog.now();
  v_today_start timestamptz :=
    (pg_catalog.date_trunc('day', pg_catalog.now() AT TIME ZONE 'Asia/Tehran')
      AT TIME ZONE 'Asia/Tehran');
  v_tomorrow_start timestamptz;
  v_total_customers bigint := 0;
  v_new_customers bigint := 0;
  v_active_customers bigint := 0;
  v_total_orders bigint := 0;
  v_today_orders bigint := 0;
  v_in_progress_orders bigint := 0;
  v_completed_orders bigint := 0;
  v_cancelled_orders bigint := 0;
  v_total_sales numeric := 0;
  v_average_order_amount numeric := 0;
  v_discount_usage_count bigint := 0;
  v_discount_amount numeric := 0;
  v_wallet_balance numeric := 0;
  v_loyalty_points bigint := 0;
  v_top_products jsonb := '[]'::jsonb;
  v_top_categories jsonb := '[]'::jsonb;
  v_top_discounts jsonb := '[]'::jsonb;
  v_payment_breakdown jsonb := '[]'::jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT COALESCE(public.is_admin(), false) THEN
    RAISE EXCEPTION 'Administrator access required' USING errcode = '42501';
  END IF;

  IF p_start_at IS NOT NULL AND p_end_at IS NOT NULL AND p_end_at <= p_start_at THEN
    RAISE EXCEPTION 'Invalid dashboard date range' USING errcode = '22023';
  END IF;

  IF p_order_source NOT IN ('all', 'customer_app', 'crm_walk_in', 'reservation') THEN
    RAISE EXCEPTION 'Invalid order source filter' USING errcode = '22023';
  END IF;

  IF p_payment_mode NOT IN ('all', 'mock', 'real') THEN
    RAISE EXCEPTION 'Invalid payment mode filter' USING errcode = '22023';
  END IF;

  v_tomorrow_start := v_today_start + interval '1 day';

  SELECT
    pg_catalog.count(*),
    pg_catalog.count(*) FILTER (
      WHERE o.status IN ('pending', 'confirmed', 'preparing', 'ready', 'out_for_delivery')
    ),
    pg_catalog.count(*) FILTER (WHERE o.status = 'completed'),
    pg_catalog.count(*) FILTER (WHERE o.status = 'cancelled'),
    COALESCE(pg_catalog.sum(o.total_amount) FILTER (WHERE o.status = 'completed'), 0),
    COALESCE(pg_catalog.avg(o.total_amount) FILTER (WHERE o.status = 'completed'), 0),
    pg_catalog.count(DISTINCT o.user_id) FILTER (
      WHERE o.user_id IS NOT NULL AND o.status <> 'cancelled'
    )
  INTO
    v_total_orders,
    v_in_progress_orders,
    v_completed_orders,
    v_cancelled_orders,
    v_total_sales,
    v_average_order_amount,
    v_active_customers
  FROM public.orders o
  WHERE (p_start_at IS NULL OR o.created_at >= p_start_at)
    AND (p_end_at IS NULL OR o.created_at < p_end_at)
    AND (p_order_source = 'all' OR o.order_source = p_order_source)
    AND (p_payment_mode = 'all' OR o.payment_mode = p_payment_mode);

  SELECT pg_catalog.count(*)
  INTO v_today_orders
  FROM public.orders o
  WHERE o.created_at >= v_today_start
    AND o.created_at < v_tomorrow_start
    AND (p_order_source = 'all' OR o.order_source = p_order_source)
    AND (p_payment_mode = 'all' OR o.payment_mode = p_payment_mode);

  SELECT pg_catalog.count(*)
  INTO v_total_customers
  FROM public.profiles p
  WHERE p.role = 'customer';

  SELECT pg_catalog.count(*)
  INTO v_new_customers
  FROM public.profiles p
  WHERE p.role = 'customer'
    AND (p_start_at IS NULL OR p.created_at >= p_start_at)
    AND (p_end_at IS NULL OR p.created_at < p_end_at);

  SELECT COALESCE(pg_catalog.sum(w.balance), 0)
  INTO v_wallet_balance
  FROM public.customer_wallets w
  JOIN public.profiles p ON p.id = w.user_id
  WHERE p.role = 'customer';

  SELECT COALESCE(pg_catalog.sum(w.total_points), 0)
  INTO v_loyalty_points
  FROM public.loyalty_wallets w
  JOIN public.profiles p ON p.id = w.user_identifier
  WHERE p.role = 'customer';

  SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x)), '[]'::jsonb)
  INTO v_top_products
  FROM (
    SELECT
      oi.product_id,
      COALESCE(NULLIF(pg_catalog.btrim(oi.product_name), ''), pr.name) AS product_name,
      pg_catalog.sum(oi.quantity)::bigint AS quantity,
      pg_catalog.sum(oi.total_price) AS total_amount
    FROM public.order_items oi
    JOIN public.orders o ON o.id = oi.order_id
    LEFT JOIN public.products pr ON pr.id = oi.product_id
    WHERE o.status = 'completed'
      AND (p_start_at IS NULL OR o.created_at >= p_start_at)
      AND (p_end_at IS NULL OR o.created_at < p_end_at)
      AND (p_order_source = 'all' OR o.order_source = p_order_source)
      AND (p_payment_mode = 'all' OR o.payment_mode = p_payment_mode)
    GROUP BY oi.product_id, COALESCE(NULLIF(pg_catalog.btrim(oi.product_name), ''), pr.name)
    ORDER BY pg_catalog.sum(oi.quantity) DESC, pg_catalog.sum(oi.total_price) DESC
    LIMIT 10
  ) x;

  SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x)), '[]'::jsonb)
  INTO v_top_categories
  FROM (
    SELECT
      c.id AS category_id,
      c.name AS category_name,
      pg_catalog.sum(oi.quantity)::bigint AS quantity,
      pg_catalog.sum(oi.total_price) AS total_amount
    FROM public.order_items oi
    JOIN public.orders o ON o.id = oi.order_id
    JOIN public.products pr ON pr.id = oi.product_id
    JOIN public.categories c ON c.id = pr.category_id
    WHERE o.status = 'completed'
      AND (p_start_at IS NULL OR o.created_at >= p_start_at)
      AND (p_end_at IS NULL OR o.created_at < p_end_at)
      AND (p_order_source = 'all' OR o.order_source = p_order_source)
      AND (p_payment_mode = 'all' OR o.payment_mode = p_payment_mode)
    GROUP BY c.id, c.name
    ORDER BY pg_catalog.sum(oi.quantity) DESC, pg_catalog.sum(oi.total_price) DESC
    LIMIT 10
  ) x;

  WITH redeemed AS (
    SELECT
      dr.order_id,
      pg_catalog.max(dr.code_snapshot) AS code,
      pg_catalog.max(dr.discount_amount) AS discount_amount
    FROM public.discount_redemptions dr
    WHERE dr.status = 'redeemed'
    GROUP BY dr.order_id
  )
  SELECT
    pg_catalog.count(*),
    COALESCE(pg_catalog.sum(r.discount_amount), 0)
  INTO v_discount_usage_count, v_discount_amount
  FROM redeemed r
  JOIN public.orders o ON o.id = r.order_id
  WHERE o.status = 'completed'
    AND (p_start_at IS NULL OR o.created_at >= p_start_at)
    AND (p_end_at IS NULL OR o.created_at < p_end_at)
    AND (p_order_source = 'all' OR o.order_source = p_order_source)
    AND (p_payment_mode = 'all' OR o.payment_mode = p_payment_mode);

  WITH redeemed AS (
    SELECT
      dr.order_id,
      pg_catalog.max(dr.code_snapshot) AS code,
      pg_catalog.max(dr.discount_amount) AS discount_amount
    FROM public.discount_redemptions dr
    WHERE dr.status = 'redeemed'
    GROUP BY dr.order_id
  )
  SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x)), '[]'::jsonb)
  INTO v_top_discounts
  FROM (
    SELECT
      r.code,
      pg_catalog.count(DISTINCT o.id)::bigint AS usage_count,
      pg_catalog.sum(r.discount_amount) AS discount_amount
    FROM redeemed r
    JOIN public.orders o ON o.id = r.order_id
    WHERE o.status = 'completed'
      AND (p_start_at IS NULL OR o.created_at >= p_start_at)
      AND (p_end_at IS NULL OR o.created_at < p_end_at)
      AND (p_order_source = 'all' OR o.order_source = p_order_source)
      AND (p_payment_mode = 'all' OR o.payment_mode = p_payment_mode)
    GROUP BY r.code
    ORDER BY pg_catalog.count(DISTINCT o.id) DESC, pg_catalog.sum(r.discount_amount) DESC
    LIMIT 10
  ) x;

  SELECT COALESCE(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'payment_mode', x.payment_mode,
        'orders', x.orders,
        'sales', x.sales
      ) ORDER BY x.payment_mode
    ),
    '[]'::jsonb
  )
  INTO v_payment_breakdown
  FROM (
    SELECT
      o.payment_mode,
      pg_catalog.count(*)::bigint AS orders,
      COALESCE(pg_catalog.sum(o.total_amount) FILTER (WHERE o.status = 'completed'), 0) AS sales
    FROM public.orders o
    WHERE (p_start_at IS NULL OR o.created_at >= p_start_at)
      AND (p_end_at IS NULL OR o.created_at < p_end_at)
      AND (p_order_source = 'all' OR o.order_source = p_order_source)
      AND (p_payment_mode = 'all' OR o.payment_mode = p_payment_mode)
    GROUP BY o.payment_mode
  ) x;

  RETURN pg_catalog.jsonb_build_object(
    'filters', pg_catalog.jsonb_build_object(
      'start_at', p_start_at,
      'end_at', p_end_at,
      'order_source', p_order_source,
      'payment_mode', p_payment_mode
    ),
    'customers', pg_catalog.jsonb_build_object(
      'total', v_total_customers,
      'new', v_new_customers,
      'active', v_active_customers
    ),
    'orders', pg_catalog.jsonb_build_object(
      'total', v_total_orders,
      'today', v_today_orders,
      'in_progress', v_in_progress_orders,
      'completed', v_completed_orders,
      'cancelled', v_cancelled_orders
    ),
    'sales', pg_catalog.jsonb_build_object(
      'total', v_total_sales,
      'average_order', v_average_order_amount
    ),
    'top_products', v_top_products,
    'top_categories', v_top_categories,
    'discounts', pg_catalog.jsonb_build_object(
      'usage_count', v_discount_usage_count,
      'total_discount_amount', v_discount_amount,
      'top_codes', v_top_discounts
    ),
    'wallet_balance_total', v_wallet_balance,
    'loyalty_points_total', v_loyalty_points,
    'payments', v_payment_breakdown,
    'updated_at', v_now
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_crm_dashboard_overview(timestamptz, timestamptz, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_crm_dashboard_overview(timestamptz, timestamptz, text, text) TO authenticated;
