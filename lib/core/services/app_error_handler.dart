import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Converts technical exceptions into short, actionable Persian messages.
class AppErrorHandler {
  AppErrorHandler._();

  static String message(Object error, {String? fallback}) {
    if (error is AppException) return error.message;
    if (error is SocketException) {
      return 'ارتباط با اینترنت برقرار نیست. اتصال خود را بررسی کنید.';
    }
    if (error is TimeoutException) {
      return 'زمان انتظار برای پاسخ سرور به پایان رسید. دوباره تلاش کنید.';
    }
    if (error is FormatException) {
      return 'اطلاعات دریافتی از سرور معتبر نیست. لطفاً دوباره تلاش کنید.';
    }
    if (error is PostgrestException) return _postgrestMessage(error);
    if (error is AuthException) return _authMessage(error);
    if (error is StorageException) return _storageMessage(error);
    if (error is FunctionException) {
      return 'ارتباط با سرویس موردنظر ناموفق بود. کمی بعد دوباره تلاش کنید.';
    }

    final raw = error.toString().toLowerCase();
    if (raw.contains('failed host lookup') ||
        raw.contains('socketexception') ||
        raw.contains('network is unreachable')) {
      return 'سرور در دسترس نیست. اتصال اینترنت خود را بررسی کنید.';
    }
    if (raw.contains('failed to fetch') || raw.contains('clientexception')) {
      return 'ارتباط با سرور برقرار نشد. اینترنت یا دسترسی سرور را بررسی کنید.';
    }
    if (raw.contains('jwt') || raw.contains('token') ||
        raw.contains('session')) {
      return 'نشست شما معتبر نیست یا پایان یافته است. دوباره وارد حساب شوید.';
    }
    return fallback ?? 'انجام عملیات با مشکل روبه‌رو شد. لطفاً دوباره تلاش کنید.';
  }

  static String _postgrestMessage(PostgrestException error) {
    switch (error.code) {
      case '42501':
        return 'شما اجازه انجام این عملیات را ندارید. سطح دسترسی حساب را بررسی کنید.';
      case '23505':
        return 'این اطلاعات قبلاً ثبت شده است و امکان ثبت تکراری وجود ندارد.';
      case '23503':
        return 'این عملیات به اطلاعات دیگری وابسته است که وجود ندارد یا حذف شده است.';
      case '23502':
        return 'بعضی از اطلاعات ضروری وارد نشده‌اند. فرم را بررسی کنید.';
      case '22P02':
        return 'قالب یکی از اطلاعات واردشده صحیح نیست.';
      case 'PGRST116':
        return 'اطلاعات موردنظر پیدا نشد یا بیش از یک نتیجه دریافت شد.';
      default:
        return 'ذخیره یا دریافت اطلاعات از پایگاه داده ناموفق بود. لطفاً دوباره تلاش کنید.';
    }
  }

  static String _authMessage(AuthException error) {
    final text = error.message.toLowerCase();
    if (text.contains('invalid login credentials')) {
      return 'ایمیل یا رمز عبور صحیح نیست.';
    }
    if (text.contains('email not confirmed')) {
      return 'ایمیل حساب هنوز تأیید نشده است.';
    }
    if (text.contains('too many requests')) {
      return 'تعداد درخواست‌ها بیش از حد مجاز است. کمی بعد دوباره تلاش کنید.';
    }
    if (text.contains('expired') || text.contains('session')) {
      return 'نشست شما پایان یافته است. دوباره وارد حساب شوید.';
    }
    return 'احراز هویت ناموفق بود. اطلاعات ورود و اتصال اینترنت را بررسی کنید.';
  }

  static String _storageMessage(StorageException error) {
    final text = error.message.toLowerCase();
    if (text.contains('permission') || text.contains('not authorized')) {
      return 'اجازه بارگذاری یا دریافت این فایل را ندارید.';
    }
    if (text.contains('size') || text.contains('payload')) {
      return 'حجم فایل بیشتر از حد مجاز است.';
    }
    return 'بارگذاری یا دریافت فایل ناموفق بود. فرمت و حجم فایل را بررسی کنید.';
  }
}

class AppException implements Exception {
  final String message;
  const AppException(this.message);

  @override
  String toString() => message;
}
