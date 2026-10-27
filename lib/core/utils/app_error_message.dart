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
    final normalized = message.toLowerCase();
    const technicalMarkers = [
      'exception',
      'postgrest',
      'socketexception',
      'failed host lookup',
      'failed to fetch',
      'stack trace',
      'row-level security',
      'permission denied',
      'clientexception',
      'supabase',
      'http exception',
    ];
    if (technicalMarkers.any(normalized.contains)) {
      return from(message, fallback: fallback);
    }
    if (RegExp(r'[\\u0600-\\u06FF]').hasMatch(message)) {
      return message;
    }
    return fallback;
  }

  static String from(
    Object error, {
    String fallback = 'انجام عملیات با مشکل روبه‌رو شد. لطفاً دوباره تلاش کنید.',
  }) {
    final message = error.toString().toLowerCase();

    if (message.contains('failed host lookup') ||
        message.contains('socketexception') ||
        message.contains('network is unreachable') ||
        message.contains('connection refused') ||
        message.contains('connection reset') ||
        message.contains('timed out') ||
        message.contains('timeout') ||
        message.contains('clientexception')) {
      return 'ارتباط با سرور برقرار نشد. اتصال اینترنت را بررسی کنید و دوباره تلاش کنید.';
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

    if (message.contains('jwt') || message.contains('session expired')) {
      return 'نشست شما منقضی شده است. دوباره وارد پنل شوید.';
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
