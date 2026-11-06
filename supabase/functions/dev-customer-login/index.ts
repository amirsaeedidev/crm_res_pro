import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
};
const reply = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), { status, headers });

function normalizePhone(input: string): string | null {
  let value = input.trim()
    .replace(/[۰-۹]/g, (d) => String("۰۱۲۳۴۵۶۷۸۹".indexOf(d)))
    .replace(/[٠-٩]/g, (d) => String("٠١٢٣٤٥٦٧٨٩".indexOf(d)))
    .replace(/\D/g, "");
  if (value.startsWith("0098")) value = value.slice(4);
  else if (value.startsWith("98")) value = value.slice(2);
  if (value.length === 10 && value.startsWith("9")) value = "0" + value;
  return /^09\d{9}$/.test(value) ? value : null;
}
function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
async function digest(value: string): Promise<string> {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
async function derivedPassword(phone: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const bytes = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(phone));
  const hex = [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
  return `Dev-${hex}-aA1!`;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return reply({ error: "METHOD_NOT_ALLOWED" }, 405);

  try {
    if (Deno.env.get("DEV_PHONE_LOGIN_ENABLED") !== "true") {
      return reply({ error: "DEVELOPMENT_LOGIN_DISABLED" }, 404);
    }
    const expectedCode = Deno.env.get("DEV_PHONE_LOGIN_CODE") ?? "";
    const hmacSecret = Deno.env.get("DEV_PHONE_LOGIN_HMAC_SECRET") ?? "";
    const allowedPhones = (Deno.env.get("DEV_PHONE_LOGIN_ALLOWED_PHONES") ?? "")
      .split(",").map(normalizePhone).filter((v): v is string => v !== null);
    if (expectedCode.length < 4 || hmacSecret.length < 32 || allowedPhones.length === 0) {
      return reply({ error: "DEVELOPMENT_LOGIN_NOT_CONFIGURED" }, 503);
    }

    const token = (req.headers.get("Authorization") ?? "").match(/^Bearer\s+(.+)$/i)?.[1];
    if (!token) return reply({ error: "ANONYMOUS_SESSION_REQUIRED" }, 401);
    const body = await req.json().catch(() => null);
    if (!body || typeof body.phone !== "string" || typeof body.code !== "string") {
      return reply({ error: "INVALID_REQUEST" }, 400);
    }
    const phone = normalizePhone(body.phone);
    if (!phone) return reply({ error: "INVALID_PHONE" }, 400);
    if (!allowedPhones.includes(phone)) return reply({ error: "PHONE_NOT_ALLOWLISTED" }, 403);
    if (!safeEqual(body.code.trim(), expectedCode)) return reply({ error: "INVALID_CODE" }, 401);

    const url = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !anonKey || !serviceKey) return reply({ error: "SERVER_CONFIGURATION_ERROR" }, 503);

    const admin = createClient(url, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    });
    const caller = await admin.auth.getUser(token);
    if (caller.error || !caller.data.user || caller.data.user.is_anonymous !== true) {
      return reply({ error: "ANONYMOUS_SESSION_REQUIRED" }, 401);
    }

    const emailHash = await digest(phone);
    const email = `dev-${emailHash.slice(0, 48)}@customer.invalid`;
    const password = await derivedPassword(phone, hmacSecret);
    const publicClient = createClient(url, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    });

    let login = await publicClient.auth.signInWithPassword({ email, password });
    if (login.error) {
      const created = await admin.auth.admin.createUser({
        email, password, email_confirm: true,
        user_metadata: { phone, account_kind: "development_customer" },
      });
      if (created.error && !/already|exists/i.test(created.error.message)) {
        return reply({ error: "CUSTOMER_IDENTITY_CREATE_FAILED" }, 500);
      }
      login = await publicClient.auth.signInWithPassword({ email, password });
    }
    if (login.error || !login.data.user || !login.data.session) {
      return reply({ error: "CUSTOMER_SESSION_CREATE_FAILED" }, 500);
    }

    const profile = await admin.from("profiles").update({ phone }).eq("id", login.data.user.id);
    if (profile.error) {
      await publicClient.auth.signOut();
      return reply({ error: "CUSTOMER_PROFILE_SYNC_FAILED" }, 500);
    }

    await admin.auth.admin.deleteUser(caller.data.user.id);
    return reply({
      access_token: login.data.session.access_token,
      refresh_token: login.data.session.refresh_token,
      token_type: login.data.session.token_type,
      expires_in: login.data.session.expires_in,
      user_id: login.data.user.id,
    });
  } catch {
    return reply({ error: "INTERNAL_SERVER_ERROR" }, 500);
  }
});
