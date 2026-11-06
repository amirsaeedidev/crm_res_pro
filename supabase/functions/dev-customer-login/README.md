# Development-only phone identity login

This endpoint is for personal development/testing only. It is not real phone verification and must never be enabled for public use.

## Supabase Edge Function secrets

Configure in Supabase Dashboard → Edge Functions → Secrets:

- `DEV_PHONE_LOGIN_ENABLED=true`
- `DEV_PHONE_LOGIN_CODE=<private test code, at least 4 characters>`
- `DEV_PHONE_LOGIN_HMAC_SECRET=<random secret, at least 32 characters>`
- `DEV_PHONE_LOGIN_ALLOWED_PHONES=<comma-separated test numbers, 09xxxxxxxxx format>`

Do not commit these values, add them to Flutter assets, or expose them to the client. Only allowlisted phone numbers can receive accounts. The HMAC secret derives a stable, unique server-side password for each normalized phone.

Supabase automatically provides `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` to Edge Functions. The service-role key is used only inside this server function.

## Auth configuration

Enable Supabase Auth → Sign In / Providers → Anonymous Sign-Ins. Flutter obtains a short-lived anonymous session to invoke this JWT-protected function. The function verifies that caller is anonymous, creates/signs in the phone-specific permanent Auth user, updates that user's profile phone, and deletes the temporary bootstrap identity.

## Flutter development run

```bash
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --dart-define=ENABLE_DEV_PHONE_LOGIN=true
```

The app also checks `kDebugMode`, so release builds reject this flow even if the define is accidentally present. Never pass `ENABLE_DEV_PHONE_LOGIN=true` to release builds.

## Existing records

This function does not reassign any existing wallet or loyalty rows. Legacy shared-account balances must be mapped and migrated separately only after ownership is verified.
