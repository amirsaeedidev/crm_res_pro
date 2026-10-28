# گزارش پیاده‌سازی و وضعیت بررسی — ۱۵ اکتبر ۲۰۲۶

## اصلاح خطاهای اولیه

- `FilePicker.platform` با API ثابت `FilePicker.pickFiles` جایگزین شده است.
- پارامتر `minLines` به ویجت `AppTextField` اضافه شده است تا فرم تخفیف بتواند از آن استفاده کند.
- import سرویس `LoggerService` در `orders_provider.dart` اضافه شده است.
- متد `OrderModel.toJson()` و سریال‌سازی اقلام سفارش به مدل اضافه شده است.
- ارجاع غیرعمومی به `RealtimeChannel.topic` حذف شده است.
- کد Supabase از `publishableKey` استفاده می‌کند؛ `SUPABASE_URL` و کلید public با `--dart-define` برای Android و Web ارسال می‌شوند.
- `withOpacity` به `withValues(alpha: ...)` تبدیل شده، استفاده‌های رایج از `DropdownButtonFormField.value` به `initialValue` تغییر کرده و import/فیلدهای بلااستفادهٔ شناخته‌شده حذف شده‌اند.
- بخشی از callbackهای async برای جلوگیری از استفاده از `BuildContext` بعد از unmount اصلاح شده‌اند.
- فایل `.env` دارای مقادیر واقعی در بسته نیست و gitignore از commit شدن `.env` جلوگیری می‌کند.

## ماژول‌های جدید

- کیف پول مالی مشتری جدا از امتیازهای وفاداری: مانده، شارژ/کاهش با علت، ثبت دفتر گردش مالی، تاریخچه و Realtime.
- انبارداری: مواد اولیه، واحد، کد انبار، هزینهٔ واحد، حد هشدار، محاسبهٔ میانگین قیمت خرید، اصلاح موجودی، ضایعات، مرجوعی، گردش انبار و ارزش تقریبی موجودی.
- دستور مصرف غذا: انتخاب مواد با Tooltip موجودی و قیمت، مقدار مصرف به ازای هر غذا و تخمین هزینه. تغییر وضعیت سفارش به `preparing` میزان مصرف را در تراکنش کم می‌کند؛ کمبود موجودی باعث rollback می‌شود. ایندکس یکتا و کنترل تکرار از کسر مجدد همان سفارش جلوگیری می‌کند.
- نوتیفیکیشن‌های ذخیره‌شونده برای سفارش جدید، رزرو، ثبت مشتری و تیکت جدید، با Subscribe به Realtime جدول `admin_notifications`.
- PDF رسید مشتری و نسخه آشپزخانه: نام و لوگو، تاریخ، نوبت روز، نوع سفارش، میز، جدول ردیف‌های اقلام، تخفیف و مبلغ نهایی. تنظیم اندازه A4/رول ۵۸/۸۰ و نمایش/مخفی‌سازی فیلدها در تنظیمات.

## تغییرات ثبت‌شده روی Supabase

- `crm_wallet_inventory_receipt_notifications`
- `crm_receipt_queue_view_update`
- `crm_inventory_consumption_idempotency_and_local_queue`
- `crm_wallet_inventory_fk_indexes`
- `crm_customer_wallet_currency_toman`
- `crm_wallet_ledger_security_inventory_movements`
- `crm_wallet_select_policy_performance`
- `crm_wallet_inventory_realtime`
- `crm_inventory_stock_column_permissions`
- `crm_queue_index_range_and_wallet_currency_consistency`

همهٔ تغییرات بالا با ابزار Supabase روی پروژه متصل اعمال شده‌اند و نسخه‌های SQL قابل تکرار در `supabase/manual/008` تا `017` قرار دارند. صحت افزودن جدول‌ها/ستون‌ها و حضور `admin_notifications` در publication مربوط به Realtime با پرس‌وجوی دیتابیس کنترل شد.

## اصلاح امنیت مهم

تابع `dev-phone-login` که قبلاً کد ثابت `1234` و امکان تنظیم رمز با Service Role داشت، به نسخهٔ غیرفعال تغییر کرد؛ اکنون `verify_jwt=true` و پاسخ مسیر توسعه `410` است. `sms-dispatch` تغییر نکرده و اعتبارسنجی سفارشی cron secret یا کاربر مدیر دارد.

بهبودهای امنیتی دیگر: RLS برای همهٔ جدول‌های جدید، محدودکردن خواندن کیف پول به مالک یا مدیر، محدودکردن نوشتن ledger از کلاینت و الزام به RPC مدیریتی برای تراکنش‌های پولی، انبار و رسیدها.

## Advisor و موارد باز

- `pg_net` همچنان در schema `public` است؛ انتقال آن بدون بررسی زمان‌بند پیامک انجام نشد. راهنما: https://supabase.com/docs/guides/database/database-linter?lint=0014_extension_in_public
- محافظت از رمزهای لو رفته هنوز غیرفعال است؛ از Auth → Settings → Password Security در Dashboard فعال شود: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection
- Advisor تعدادی `SECURITY DEFINER` قابل اجرا توسط `authenticated` گزارش می‌کند. توابع مدیریتی جدید `public.is_admin()` را کنترل می‌کنند؛ این موارد همچنان باید با نقش‌ها و RLS در پنل بازبینی شوند، چون Advisor نمی‌تواند همهٔ کنترل‌های بدنه را تحلیل کند.
- هشدار indexهای unused در دیتابیس کم‌ترافیک به‌تنهایی دلیل حذف نیست؛ حذف خودکار انجام نشده است. ایندکس‌های کلید خارجی جدید اضافه شده‌اند.

## محدودیت اعتبارسنجی در این محیط

Flutter/Dart SDK در محیط ساخت نصب نبود. به همین دلیل `flutter analyze`, `flutter test`, `flutter build apk` و `flutter build web` اجرا نشده‌اند و نمی‌توان ادعا کرد همهٔ ۱۰۱ مورد بدون warning باقی نمانده‌اند. در ماشین توسعه این دستورات را اجرا کنید:

```powershell
flutter pub get
flutter analyze
flutter test
```

پس از آن Android و Web را جداگانه build کنید و چاپ/اشتراک PDF، realtime، شارژ و کاهش موجودی، ثبت ضایعات/مرجوعی و rollback در زمان کمبود مواد را آزمایش کنید.
