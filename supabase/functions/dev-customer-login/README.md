# Development-only phone identity login

This endpoint is strictly for personal development/testing. It is not real phone verification and must never be enabled for public use.

## Supabase Edge Function secrets

Configure in Supabase Dashboard → Edge Functions → Secrets:

- `DEV_PHONE_LOGIN_ENABLED=true`
- `DEV_PHONE_LOGIN_CLIENT_KEY=<random value with at least 32 characters>`
- `DEV_PHONE_LOGIN_CODE=<private test code>`
- `DEV_PHONE_LOGIN_HMAC_SECRET=<random secret with at least 32 characters>`
- `DEV_PHONE_LOGIN_ALLOWED_PHONES=<comma-separated test numbers in 09xxxxxxxxx format>`

Do not commit these values. The HMAC secret derives a stable server-side password per normalized phone. The client key is passed only by a local debug build; it is extractable from a compiled app and is not a production secret. The phone allowlist is the additional server-side restriction.

Supabase automatically provides `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` to Edge Functions. The service-role key is used only inside this function and never sent to Flutter.

## Deployment

Deploy this function with `verify_jwt=false` because it authenticates the personal development client using its own server-checked header. The function fails closed unless all required secrets are configured. Do not change the existing disabled `dev-phone-login` endpoint.

## Flutter development run

```bash
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --dart-define=ENABLE_DEV_PHONE_LOGIN=true --dart-define=DEV_PHONE_LOGIN_CLIENT_KEY=...
```

The app also checks `kDebugMode`, so release builds reject this flow even if the define is accidentally present. Never pass either development define to release builds, and never distribute this debug build.

## Existing records

This function does not reassign any existing wallet or loyalty rows. Legacy shared-account balances must be mapped and migrated separately only after ownership is verified.
