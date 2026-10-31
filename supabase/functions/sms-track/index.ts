import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const secretMap = (() => { try { return JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}"); } catch { return {}; } })();
const serviceKey = secretMap.default ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const admin = createClient(supabaseUrl, serviceKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

Deno.serve(async (req: Request) => {
  if (req.method !== "GET") return new Response("Method not allowed", { status: 405 });
  if (!supabaseUrl || !serviceKey) return new Response("Tracking service is not configured", { status: 503 });

  const token = new URL(req.url).searchParams.get("t") ?? "";
  if (token.length < 40 || token.length > 100) return new Response("Invalid tracking link", { status: 404 });

  const { data: tracking, error } = await admin.from("sms_campaign_tracking_tokens")
    .select("outbox_id,campaign_id,recipient_user_id")
    .eq("token", token)
    .maybeSingle();
  if (error || !tracking) return new Response("Tracking link not found", { status: 404 });

  const { error: clickError } = await admin.from("sms_campaign_clicks").insert({
    outbox_id: tracking.outbox_id,
    campaign_id: tracking.campaign_id,
    recipient_user_id: tracking.recipient_user_id,
  });
  if (clickError) return new Response("Unable to record click", { status: 503 });

  const destination = (Deno.env.get("CUSTOMER_APP_URL") ?? "").trim();
  if (!destination) {
    return new Response(
      "کلیک شما ثبت شد. آدرس عمومی اپلیکیشن رستوران هنوز برای لینک‌های کمپین تنظیم نشده است.",
      { status: 503, headers: { "Content-Type": "text/plain; charset=utf-8" } },
    );
  }

  const target = new URL(destination);
  target.searchParams.set("utm_source", "sms");
  target.searchParams.set("utm_medium", "campaign");
  target.searchParams.set("utm_campaign", tracking.campaign_id);
  return Response.redirect(target.toString(), 302);
});
