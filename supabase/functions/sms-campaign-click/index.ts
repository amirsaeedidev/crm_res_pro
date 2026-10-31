import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

const url = Deno.env.get("SUPABASE_URL") ?? "";
const keys = (() => {
  try { return JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}"); }
  catch { return {}; }
})();
const serviceKey = keys.default ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const db = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });

Deno.serve(async (req: Request) => {
  if (req.method !== "GET") return new Response("Method not allowed", { status: 405 });
  if (!url || !serviceKey) return new Response("Tracking is unavailable", { status: 503 });

  const token = new URL(req.url).searchParams.get("token")?.trim() ?? "";
  if (!/^[a-f0-9]{64}$/i.test(token)) return new Response("Invalid tracking link", { status: 404 });

  const { data: tracking, error } = await db.from("sms_campaign_tracking_tokens")
    .select("outbox_id,campaign_id,recipient_user_id,destination_url")
    .eq("token", token).maybeSingle();
  if (error || !tracking?.destination_url) return new Response("Tracking link not found", { status: 404 });

  let destination: URL;
  try {
    destination = new URL(tracking.destination_url);
    if (!["http:", "https:"].includes(destination.protocol)) throw new Error("Unsupported protocol");
  } catch {
    return new Response("Invalid destination", { status: 400 });
  }

  const { error: clickError } = await db.from("sms_campaign_clicks").insert({
    campaign_id: tracking.campaign_id,
    outbox_id: tracking.outbox_id,
    recipient_user_id: tracking.recipient_user_id,
    clicked_at: new Date().toISOString(),
  });
  if (clickError) return new Response("Unable to record click", { status: 503 });

  return new Response(null, {
    status: 302,
    headers: { Location: destination.toString(), "Cache-Control": "no-store" },
  });
});
