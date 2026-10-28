import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// Development OTP authentication was intentionally disabled in production.
// Deploy this function with JWT verification enabled if keeping the stub.
Deno.serve((req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      },
    });
  }

  return new Response(JSON.stringify({
    error: "این مسیر ورود آزمایشی غیرفعال شده است. از روش احراز هویت امن برنامه استفاده کنید.",
    code: "DEVELOPMENT_LOGIN_DISABLED",
  }), {
    status: 410,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
});
