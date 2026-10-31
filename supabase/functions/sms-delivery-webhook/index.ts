import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

const url = Deno.env.get("SUPABASE_URL") ?? "";
const keys = (() => {
  try { return JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}"); }
  catch { return {}; }
})();
const serviceKey = keys.default ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const callbackSecret = Deno.env.get("SMS_DELIVERY_WEBHOOK_SECRET") ?? "";
const db = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, x-sms-delivery-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers });
}

function safeEqual(a: string, b: string): boolean {
  if (!a || !b || a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return mismatch === 0;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return response({ error: "POST required" }, 405);
  if (!url || !serviceKey || !callbackSecret) return response({ error: "Webhook secrets are not configured." }, 503);
  if (!safeEqual(req.headers.get("x-sms-delivery-secret") ?? "", callbackSecret)) {
    return response({ error: "Unauthorized" }, 401);
  }

  try {
    const payload = await req.json() as Record<string, unknown>;
    const messageId = String(payload.providerMessageId ?? payload.messageId ?? payload.Value ?? payload.value ?? "").trim();
    const rawStatus = String(payload.deliveryStatus ?? payload.status ?? payload.Status ?? "").toLowerCase();
    const delivered = ["delivered", "delivery", "success", "ارسال شده به گیرنده", "تحویل شده", "تحویل‌شده", "1"].includes(rawStatus);
    const undelivered = ["undelivered", "failed", "failure", "not_delivered", "ناموفق", "تحویل نشده", "0"].includes(rawStatus);
    if (!messageId || (!delivered && !undelivered)) {
      return response({ error: "Expected providerMessageId/messageId and a supported delivery status." }, 400);
    }

    const { data, error } = await db.rpc("sms_apply_delivery_report", {
      p_provider_message_id: messageId,
      p_status: delivered ? "delivered" : "undelivered",
      p_delivery_code: String(payload.code ?? payload.Code ?? "").slice(0, 100),
      p_error: String(payload.error ?? payload.description ?? payload.Description ?? "").slice(0, 500),
    });
    if (error) return response({ error: "Unable to persist delivery report." }, 500);
    return response(data);
  } catch {
    return response({ error: "Invalid delivery callback payload." }, 400);
  }
});
