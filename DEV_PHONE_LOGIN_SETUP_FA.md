# ورود آزمایشی امن مشتری (فقط محیط توسعه)

این مسیر برای تست شخصی است و جایگزین احراز هویت واقعی مشتریان در انتشار عمومی نیست.

## رفتار

- هر شماره مجاز به یک حساب مستقل Supabase Auth نگاشت می‌شود.
- شناسه Auth همان کاربر قبلیِ دارای همان شماره را حفظ می‌کند؛ بنابراین پروفایل و داده‌های متصل به آن شناسه جابه‌جا نمی‌شوند.
- کد ورود و فهرست شماره‌های مجاز فقط در Secrets سمت Supabase نگهداری می‌شوند.
- رمز حساب‌های آزمایشی با HMAC و یک راز ۳۲ کاراکتری یا طولانی‌تر در سمت Edge Function مشتق می‌شود.
- Edge Function به JWT معتبر نیاز دارد و ورود فقط در Debug اپ مشتری فعال می‌شود.
- مسیر عمومی/Release اپ از این روش استفاده نمی‌کند.

## تنظیم Secrets در Supabase

در Dashboard پروژه، به **Edge Functions → Secrets** برو و این مقادیر را اضافه کن:

| Secret | مقدار |
|---|---|
| `DEV_PHONE_LOGIN_ENABLED` | `true` |
| `DEV_PHONE_LOGIN_CODE` | یک کد آزمایشی ۶ رقمی که فقط خودت می‌دانی |
| `DEV_PHONE_LOGIN_ALLOWED_PHONES` | شماره‌های تست مجاز، جداشده با کاما؛ قالب ایران بدون +، مانند `989123456789` |
| `DEV_PHONE_LOGIN_PASSWORD_SECRET` | یک راز تصادفی حداقل ۳۲ کاراکتری |

از قرار دادن `service_role`، کد آزمایشی یا راز HMAC در Flutter، `.env` قابل انتشار یا GitHub خودداری کن. متغیرهای پیش‌فرض `SUPABASE_URL`، `SUPABASE_ANON_KEY` و `SUPABASE_SERVICE_ROLE_KEY` توسط محیط Supabase Function تأمین می‌شوند.

شماره‌ها را فقط زمانی به allowlist اضافه کن که متعلق به خودت و مخصوص تست باشند. از شماره مشتری واقعی استفاده نکن. برای غیرفعال کردن فوری این مسیر، مقدار `DEV_PHONE_LOGIN_ENABLED` را به `false` تغییر بده یا Secrets مربوط به این قابلیت را حذف کن.

## اجرای اپ مشتری

در حالت Debug اجرا کن و فلگ زیر را اضافه کن:

```bash
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_OR_ANON_KEY --dart-define=DEV_PHONE_LOGIN_ENABLED=true
```

کد ۶ رقمی‌ای که در `DEV_PHONE_LOGIN_CODE` ثبت کرده‌ای را در صفحه ورود وارد کن. بدون فلگ Debug، این روش در اپ غیرفعال است.

## محدودیت امنیتی

این روش فقط برای توسعه و تست شخصی است. کد آزمایشی مشترک، حتی با allowlist، اثبات مالکیت شماره تلفن محسوب نمی‌شود. پیش از انتشار عمومی باید این Secrets غیرفعال/حذف شوند و ورود واقعی با SMS OTP یا ارائه‌دهنده احراز هویت مناسب فعال شود. محدودکننده تلاش فعلی در حافظه هر Edge Function instance است و جایگزین rate limit توزیع‌شده برای محیط عمومی نیست.
