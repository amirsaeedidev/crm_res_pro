/// Converts technical failures into concise, Persian user-facing messages.
/// Keep the original exception in application logs, not in the visible UI.
class AppErrorMessage {
  AppErrorMessage._();

  /// Keeps friendly Persian messages, but prevents technical exceptions
  /// from being shown directly by shared error widgets.
  static String forDisplay(
    String message, {
    String fallback = 'نمایش اطلاعات با مشکل روبه‌رو شد. لطفاً دوباره تلاش کنید.',
  }) {
    final cleaned = message
        .replaceAll('Exception: ', '')
        .replaceAll('exception: ', '')
        .trim();
    final normalized = cleaned.toLowerCase();
    const technicalMarkers = [
      'postgrest',
      'socketexception',
      'failed host lookup',
      'failed to fetch',
      'xmlhttprequest',
      'network request failed',
      'handshakeexception',
      'stack trace',
      'row-level security',
      'permission denied',
      'clientexception',
      'supabase',
      'http exception',
      'timed out',
      'timeout',
    ];
    if (technicalMarkers.any(normalized.contains)) {
      return from(cleaned, fallback: fallback);
    }
    final containsPersian = RegExp(r'[\u0600-\u06FF]').hasMatch(cleaned);
    final containsEnglishText = RegExp(r'[A-Za-z]{3,}').hasMatch(cleaned);
    if (containsPersian && !containsEnglishText) return cleaned;
    if (containsEnglishText) return from(cleaned, fallback: fallback);
    return fallback;
  }

  static String from(
    Object error, {
    String fallback = 'انجام عملیات با مشکل روبه‌رو شد. لطفاً دوباره تلاش کنید.',
  }) {
    final message = error.toString().toLowerCase();

    if (message.contains('failed host lookup') ||
        message.contains('socketexception') ||
        message.contains('xmlhttprequest') ||
        message.contains('network request failed') ||
        message.contains('handshakeexception') ||
        message.contains('network is unreachable') ||
        message.contains('connection refused') ||
        message.contains('connection reset') ||
        message.contains('timed out') ||
        message.contains('timeout') ||
        message.contains('clientexception')) {
      return 'ارتباط با سرور برقرار نشد. اینترنت یا اتصال شبکه را بررسی کنید و دوباره تلاش کنید.';
    }

    if (message.contains('row-level security') ||
        message.contains('permission denied') ||
        message.contains('not authorized') ||
        message.contains('unauthorized') ||
        message.contains('42501') ||
        message.contains('forbidden')) {
      return 'اجازه انجام این عملیات را ندارید. سطح دسترسی حساب را بررسی کنید.';
    }

    if (message.contains('duplicate key') ||
        message.contains('unique constraint') ||
        message.contains('23505')) {
      return 'این اطلاعات قبلاً ثبت شده است. مقدار دیگری وارد کنید.';
    }

    if (message.contains('foreign key') ||
        message.contains('23503')) {
      return 'این مورد به اطلاعات دیگری وابسته است و اکنون قابل تغییر یا حذف نیست.';
    }

    if (message.contains('invalid login credentials') ||
        message.contains('invalid password') ||
        message.contains('invalid email')) {
      return 'اطلاعات ورود معتبر نیست. ایمیل و رمز عبور را بررسی کنید.';
    }

    if (message.contains('email not confirmed') ||
        message.contains('email_not_confirmed')) {
      return 'نشانی ایمیل تأیید نشده است. ابتدا ایمیل خود را تأیید کنید.';
    }

    if (message.contains('user already registered') ||
        message.contains('already registered') ||
        message.contains('already exists')) {
      return 'این حساب یا اطلاعات قبلاً ثبت شده است.';
    }

    if (message.contains('too many requests') ||
        message.contains('rate limit') ||
        message.contains('over_request_rate_limit')) {
      return 'تعداد درخواست‌ها بیش از حد مجاز است. کمی صبر کنید و دوباره تلاش کنید.';
    }

    if (message.contains('password should be at least') ||
        message.contains('password is too short')) {
      return 'رمز عبور کوتاه است. رمز قوی‌تری انتخاب کنید.';
    }

    if (message.contains('jwt') ||
        message.contains('session expired') ||
        message.contains('session_not_found')) {
      return 'نشست ورود شما منقضی شده است. دوباره وارد پنل شوید.';
    }

    if (message.contains('bucket not found') ||
        message.contains('object not found') ||
        message.contains('storage/object-not-found')) {
      return 'فایل یا فضای ذخیره‌سازی موردنظر پیدا نشد.';
    }

    if (message.contains('file size exceeds') ||
        message.contains('payload too large')) {
      return 'حجم فایل بیشتر از حد مجاز است. فایل کوچک‌تری انتخاب کنید.';
    }

    if (message.contains('invalid mime type') ||
        message.contains('mime type not supported') ||
        message.contains('unsupported media type')) {
      return 'قالب این فایل پشتیبانی نمی‌شود. فایل دیگری انتخاب کنید.';
    }

    if (message.contains('not found') || message.contains('404')) {
      return 'اطلاعات درخواستی پیدا نشد یا دیگر در دسترس نیست.';
    }

    if (message.contains('postgrest') ||
        message.contains('supabase') ||
        message.contains('failed to fetch') ||
        message.contains('http exception')) {
      return 'دریافت اطلاعات از سرور ناموفق بود. لطفاً دوباره تلاش کنید.';
    }

    // Never display unknown exception text directly; it may contain
    // technical English, SQL details, or implementation information.
    return fallback;
  }
}
