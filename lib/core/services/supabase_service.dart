import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import 'app_error_handler.dart';
import 'logger_service.dart';

class SupabaseService {
  SupabaseService._();

  static SupabaseClient? _client;

  static SupabaseClient get client {
    final instance = _client;
    if (instance == null) {
      throw const AppException(
        'ارتباط با سرویس داده هنوز راه‌اندازی نشده است. برنامه را دوباره اجرا کنید.',
      );
    }
    return instance;
  }

  static Future<void> initialize() async {
    try {
      if (SupabaseConfig.url.isEmpty ||
          SupabaseConfig.publishableKey.isEmpty) {
        throw const AppException(
          'تنظیمات اتصال به سرور کامل نیست. نشانی سرور و کلید عمومی را بررسی کنید.',
        );
      }
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
        debug: false,
      );
      _client = Supabase.instance.client;
      LoggerService.info('Supabase initialized successfully');
    } catch (error, stackTrace) {
      LoggerService.error(
        'Supabase initialization failed',
        error: error,
        stackTrace: stackTrace,
      );
      throw AppException(
        AppErrorHandler.message(
          error,
          fallback: 'راه‌اندازی ارتباط با سرور ناموفق بود. تنظیمات اتصال را بررسی کنید.',
        ),
      );
    }
  }

  static Future<T> run<T>(
    Future<T> Function() request, {
    String? fallbackMessage,
  }) async {
    try {
      return await request();
    } catch (error, stackTrace) {
      LoggerService.error(
        'Supabase request failed',
        error: error,
        stackTrace: stackTrace,
      );
      throw AppException(
        AppErrorHandler.message(error, fallback: fallbackMessage),
      );
    }
  }

  static GoTrueClient get auth => client.auth;
  static SupabaseQueryBuilder from(String table) => client.from(table);
  static SupabaseStorageClient get storage => client.storage;
  static RealtimeClient get realtime => client.realtime;
}
