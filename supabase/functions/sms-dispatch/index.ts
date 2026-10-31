import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const secretMap = (() => {
  try { return JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}"); }
  catch { return {}; }
})();
const SUPABASE_SERVER_KEY = secretMap.default ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const admin = createClient(SUPABASE_URL, SUPABASE_SERVER_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type, x-sms-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};

type OutboxRow = {
  id: string;
  event_key: string;
  recipient_user_id: string | null;
  recipient_phone: string;
  send_mode: "normal" | "pattern";
  normal_message: string;
  pattern_body_id: string;
  pattern_args: string[] | null;
  attempts: number;
  max_attempts: number;
  campaign_id?: string | null;
  tracking_url?: string;
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: corsHeaders });
}

function constantTimeEqual(a: string, b: string): boolean {
  if (!a || !b || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function isAuthorized(req: Request, cronSecret: string): Promise<boolean> {
  if (constantTimeEqual(req.headers.get("x-sms-cron-secret") ?? "", cronSecret)) return true;
  const match = (req.headers.get("authorization") ?? "").match(/^Bearer\s+(.+)$/i);
  if (!match) return false;
  const { data: userResult, error: userError } = await admin.auth.getUser(match[1]);
  if (userError || !userResult.user) return false;
  const { data: profile, error: profileError } = await admin.from("profiles")
    .select("role,status").eq("id", userResult.user.id).maybeSingle();
  return !profileError && !!profile && profile.role === "admin" && profile.status === "active";
}

async function getTrackingUrl(row: OutboxRow): Promise<string | undefined> {
  if (row.event_key !== "marketing_campaign" || !row.campaign_id) return undefined;
  const { data: existing } = await admin.from("sms_campaign_tracking_tokens")
    .select("token").eq("outbox_id", row.id).maybeSingle();
  let token = existing?.token as string | undefined;
  if (!token) {
    token = crypto.randomUUID().replaceAll("-", "") + crypto.randomUUID().replaceAll("-", "");
    const { data, error } = await admin.from("sms_campaign_tracking_tokens")
      .insert({
        outbox_id: row.id,
        campaign_id: row.campaign_id,
        recipient_user_id: row.recipient_user_id,
        token,
      }).select("token").single();
    if (error) throw new Error("Unable to create campaign tracking token");
    token = data.token as string;
  }
  const baseUrl = SUPABASE_URL.endsWith("/") ? SUPABASE_URL.slice(0, -1) : SUPABASE_URL;
  return baseUrl + "/functions/v1/sms-track?t=" + encodeURIComponent(token);
}

function formBody(values: Record<string, string>) {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(values)) params.set(key, value);
  return params.toString();
}

function parseProviderResponse(raw: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === "object") return parsed as Record<string, unknown>;
  } catch { /* Provider body is parsed only here and never exposed to the client. */ }
  return { Value: raw.trim() };
}

async function sendToMelipayamak(
  row: OutboxRow,
  settings: Record<string, unknown>,
  username: string,
  apiKey: string,
): Promise<{ ok: boolean; providerId?: string; code: string; error?: string; durationMs: number }> {
  const started = Date.now();
  const isPattern = row.send_mode === "pattern";
  const endpoint = isPattern
    ? "https://rest.payamak-panel.com/api/SendSMS/BaseServiceNumber"
    : "https://rest.payamak-panel.com/api/SendSMS/SendSMS";
  const fields: Record<string, string> = { username, password: apiKey, to: row.recipient_phone };

  if (isPattern) {
    const bodyId = row.pattern_body_id || String(settings.default_body_id ?? "");
    if (!bodyId.trim()) return { ok: false, code: "CONFIG", error: "Pattern Body ID is not configured.", durationMs: Date.now() - started };
    fields.text = (row.pattern_args ?? []).join(";");
    fields.bodyId = bodyId;
  } else {
    const sender = String(settings.sender_number ?? "").trim();
    if (!sender) return { ok: false, code: "CONFIG", error: "Normal SMS sender number is not configured.", durationMs: Date.now() - started };
    fields.from = sender;
    fields.text = row.tracking_url
      ? row.normal_message.trim() + '\\n' + row.tracking_url
      : row.normal_message;
    fields.isFlash = "false";
  }

  let response: Response;
  let raw: string;
  try {
    response = await fetch(endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded; charset=utf-8" },
      body: formBody(fields),
      signal: AbortSignal.timeout(12000),
    });
    raw = await response.text();
  } catch {
    // Ambiguous carrier/network outcome is marked UNKNOWN by the finalizer and is not retried,
    // to avoid sending duplicate messages if the provider accepted the request before timeout.
    return { ok: false, code: "UNKNOWN", error: "No definitive response from SMS provider; automatic retry stopped to avoid duplicates.", durationMs: Date.now() - started };
  }

  const payload = parseProviderResponse(raw);
  const retStatus = Number(payload.RetStatus);
  const value = payload.Value == null ? "" : String(payload.Value);
  const providerMessage = payload.StrRetStatus == null ? "" : String(payload.StrRetStatus);
  if (response.ok && Number.isFinite(retStatus) && retStatus === 1) {
    return { ok: true, providerId: value.slice(0, 200) || undefined, code: "1", durationMs: Date.now() - started };
  }
  if (response.ok && payload.RetStatus == null && /^\d{8,}$/.test(value)) {
    return { ok: true, providerId: value.slice(0, 200), code: "VALUE_ONLY", durationMs: Date.now() - started };
  }
  const safeCode = payload.RetStatus == null ? String(response.status) : String(payload.RetStatus);
  return {
    ok: false,
    code: safeCode.slice(0, 100),
    error: (providerMessage || `SMS provider rejected the request (code ${safeCode}).`).slice(0, 450),
    durationMs: Date.now() - started,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "POST required" }, 405);
  if (!SUPABASE_URL || !SUPABASE_SERVER_KEY) return json({ error: "Supabase server secrets are not configured." }, 500);

  try {
    const { data: config, error: configError } = await admin.rpc("sms_worker_get_config");
    if (configError || !config || typeof config !== "object") return json({ error: "SMS worker configuration unavailable." }, 503);
    const settings = (config.settings ?? {}) as Record<string, unknown>;
    const username = String(settings.username ?? "").trim();
    const apiKey = String(config.api_key ?? "");
    const cronSecret = String(config.cron_secret ?? "");
    if (!(await isAuthorized(req, cronSecret))) return json({ error: "Unauthorized" }, 401);
    if (settings.sms_enabled !== true) return json({ processed: 0, sent: 0, retried: 0, failed: 0, skipped: "SMS is disabled in settings." });
    if (!username || !apiKey) return json({ processed: 0, sent: 0, retried: 0, failed: 0, skipped: "Melipayamak credentials are not configured." });

    let requestedBatch = 20;
    try {
      const body = await req.json();
      if (body && Number.isInteger(body.batchSize)) requestedBatch = Number(body.batchSize);
    } catch { /* Empty scheduled payload is valid. */ }
    const batchSize = Math.max(1, Math.min(20, requestedBatch));
    const { data: rows, error: claimError } = await admin.rpc("sms_claim_pending_batch", { p_limit: batchSize });
    if (claimError) return json({ error: "Unable to claim pending SMS queue." }, 500);

    const summary = { processed: 0, sent: 0, retried: 0, failed: 0 };
    for (const row of (rows ?? []) as OutboxRow[]) {
      summary.processed++;
      try {
        row.tracking_url = await getTrackingUrl(row);
      } catch {
        summary.failed++;
        await admin.rpc('sms_finalize_attempt', {
          p_outbox_id: row.id, p_success: false, p_response_code: 'TRACKING',
          p_error_message: 'Campaign tracking link could not be prepared.', p_duration_ms: 0,
        });
        continue;
      }
      const outcome = await sendToMelipayamak(row, settings, username, apiKey);
      const { data: finalized, error: finalizeError } = await admin.rpc("sms_finalize_attempt", {
        p_outbox_id: row.id,
        p_success: outcome.ok,
        p_provider_message_id: outcome.providerId ?? null,
        p_response_code: outcome.code,
        p_error_message: outcome.error ?? null,
        p_duration_ms: outcome.durationMs,
      });
      if (finalizeError) { summary.failed++; continue; }
      const status = String(finalized?.status ?? "");
      if (status === "sent") summary.sent++;
      else if (status === "retry") summary.retried++;
      else summary.failed++;
    }
    return json(summary);
  } catch {
    // Do not return provider credentials, recipient phone numbers, or message content.
    return json({ error: "SMS dispatch failed unexpectedly. Inspect server-side logs." }, 500);
  }
});
