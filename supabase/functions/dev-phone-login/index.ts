import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
};

const failedAttempts = new Map<string, number[]>();
const WINDOW_MS = 10 * 60 * 1000;
const MAX_FAILED_ATTEMPTS = 6;

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

function normalizePhone(input: string): string {
  let digits = input.replace(/[^0-9]/g, "");
  if (digits.startsWith("0098")) {
    digits = digits.slice(2);
  } else if (digits.startsWith("0")) {
    digits = `98${digits.slice(1)}`;
  } else if (digits.length === 10 && digits.startsWith("9")) {
    digits = `98${digits}`;
  }
  return digits;
}

function constantTimeEquals(left: string, right: string): boolean {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a[i] ^ b[i];
  return difference === 0;
}

async function derivePassword(phone: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(`restaurant-dev-login:${phone}`),
  );
  return Array.from(new Uint8Array(signature))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function isRateLimited(phone: string): boolean {
  const now = Date.now();
  const recent = (failedAttempts.get(phone) ?? []).filter((time) => now - time < WINDOW_MS);
  failedAttempts.set(phone, recent);
  return recent.length >= MAX_FAILED_ATTEMPTS;
}

function recordFailedAttempt(phone: string): void {
  const now = Date.now();
  const recent = (failedAttempts.get(phone) ?? []).filter((time) => now - time < WINDOW_MS);
  recent.push(now);
  failedAttempts.set(phone, recent);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ code: "METHOD_NOT_ALLOWED" }, 405);

  const enabled = Deno.env.get("DEV_PHONE_LOGIN_ENABLED") === "true";
  const expectedCode = Deno.env.get("DEV_PHONE_LOGIN_CODE") ?? "";
  const allowedPhones = (Deno.env.get("DEV_PHONE_LOGIN_ALLOWED_PHONES") ?? "")
    .split(",")
    .map((value) => normalizePhone(value.trim()))
    .filter(Boolean);
  const passwordSecret = Deno.env.get("DEV_PHONE_LOGIN_PASSWORD_SECRET") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

  if (
    !enabled || expectedCode.length < 4 || allowedPhones.length === 0 ||
    passwordSecret.length < 32 || !supabaseUrl || !serviceRoleKey || !anonKey
  ) {
    return json({ code: "DEVELOPMENT_LOGIN_NOT_CONFIGURED" }, 503);
  }

  let body: { phone?: unknown; code?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ code: "INVALID_REQUEST" }, 400);
  }

  if (typeof body.phone !== "string" || typeof body.code !== "string") {
    return json({ code: "INVALID_REQUEST" }, 400);
  }

  const phone = normalizePhone(body.phone);
  if (!/^989[0-9]{9}$/.test(phone) || !allowedPhones.includes(phone)) {
    return json({ code: "PHONE_NOT_ALLOWED" }, 403);
  }

  if (isRateLimited(phone)) {
    return json({ code: "TOO_MANY_ATTEMPTS" }, 429);
  }

  if (!constantTimeEquals(body.code, expectedCode)) {
    recordFailedAttempt(phone);
    return json({ code: "INVALID_CODE" }, 401);
  }

  try {
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const email = `dev-${phone}@dev.restaurant.test`;
    const password = await derivePassword(phone, passwordSecret);

    const { data: existingProfile, error: profileLookupError } = await admin
      .from("profiles")
      .select("id")
      .eq("phone", phone)
      .maybeSingle();

    if (profileLookupError) {
      return json({ code: "PROFILE_LOOKUP_FAILED" }, 500);
    }

    let userId: string;
    if (existingProfile?.id) {
      userId = existingProfile.id as string;
      const { data: existingUser, error: getUserError } =
        await admin.auth.admin.getUserById(userId);
      if (getUserError || !existingUser.user) {
        return json({ code: "EXISTING_USER_NOT_FOUND" }, 500);
      }

      const { error: updateError } = await admin.auth.admin.updateUserById(
        userId,
        {
          email,
          password,
          email_confirm: true,
          user_metadata: {
            ...(existingUser.user.user_metadata ?? {}),
            phone,
            auth_mode: "development_mock",
          },
        },
      );
      if (updateError) return json({ code: "EXISTING_USER_UPDATE_FAILED" }, 500);
    } else {
      const { data: created, error: createError } =
        await admin.auth.admin.createUser({
          email,
          password,
          email_confirm: true,
          user_metadata: { phone, auth_mode: "development_mock" },
        });
      if (createError || !created.user) {
        return json({ code: "USER_CREATION_FAILED" }, 500);
      }
      userId = created.user.id;

      const { error: profileUpdateError } = await admin
        .from("profiles")
        .update({ phone })
        .eq("id", userId);
      if (profileUpdateError) return json({ code: "PROFILE_SYNC_FAILED" }, 500);
    }

    const publicClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: signedIn, error: signInError } =
      await publicClient.auth.signInWithPassword({ email, password });

    if (signInError || !signedIn.session) {
      return json({ code: "SESSION_CREATION_FAILED" }, 500);
    }

    failedAttempts.delete(phone);
    return json({
      access_token: signedIn.session.access_token,
      refresh_token: signedIn.session.refresh_token,
      expires_in: signedIn.session.expires_in,
      token_type: signedIn.session.token_type,
    });
  } catch {
    return json({ code: "DEVELOPMENT_LOGIN_FAILED" }, 500);
  }
});
