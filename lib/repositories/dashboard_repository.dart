import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/logger_service.dart';
import '../core/services/supabase_service.dart';
import '../models/statistics_model.dart';
import '../models/order_model.dart';

class DashboardRepository {
  final SupabaseClient _client = SupabaseService.client;

  /// All dashboard aggregates are calculated in one guarded Supabase RPC.
  Future<StatisticsModel> getStatistics({
    DateTime? startAt,
    DateTime? endAt,
    String orderSource = 'all',
    String paymentMode = 'all',
  }) async {
    try {
      final dynamic response = await _client.rpc(
        'get_crm_dashboard_overview',
        params: {
          'p_start_at': startAt?.toUtc().toIso8601String(),
          'p_end_at': endAt?.toUtc().toIso8601String(),
          'p_order_source': orderSource,
          'p_payment_mode': paymentMode,
        },
      );

      if (response is! Map) {
        throw FormatException(
          'پاسخ تابع get_crm_dashboard_overview باید یک JSON object باشد؛ '
          'نوع دریافت‌شده: ${response.runtimeType}',
        );
      }

      return StatisticsModel.fromJson(Map<String, dynamic>.from(response));
    } on PostgrestException catch (e, st) {
      LoggerService.error(
        'Fetch dashboard overview failed',
        error: e,
        stackTrace: st,
      );

      if (e.code == '42501' ||
          e.message.contains('Administrator access required')) {
        throw Exception(
          'دسترسی به آمار داشبورد مجاز نیست. '
          'نقش مدیر و نشست ورود را بررسی کنید.',
        );
      }

      throw Exception(
        'خطا در دریافت آمار داشبورد '
        '(کد ${e.code ?? 'نامشخص'}): ${e.message}',
      );
    } on FormatException catch (e, st) {
      LoggerService.error(
        'Invalid dashboard overview response',
        error: e,
        stackTrace: st,
      );
      throw Exception(e.message);
    } catch (e, st) {
      LoggerService.error(
        'Unexpected dashboard overview error',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Fetch the most recent orders from the real database.
  Future<List<OrderModel>> getRecentOrders({int limit = 5}) async {
    final safeLimit = limit.clamp(1, 100).toInt();

    try {
      final dynamic response = await _client
          .from('orders_view')
          .select('*')
          .order('created_at', ascending: false)
          .limit(safeLimit);

      if (response is! List) {
        throw const FormatException('پاسخ سفارش‌های اخیر باید یک لیست باشد.');
      }

      return response
          .map<OrderModel>((row) {
            if (row is! Map) {
              throw const FormatException(
                'ساختار یکی از سفارش‌های دریافتی معتبر نیست.',
              );
            }
            return OrderModel.fromJson(Map<String, dynamic>.from(row));
          })
          .toList(growable: false);
    } on PostgrestException catch (e, st) {
      LoggerService.error(
        'Fetch recent orders failed',
        error: e,
        stackTrace: st,
      );
      throw Exception(
        'خطا در دریافت سفارش‌های اخیر '
        '(کد ${e.code ?? 'نامشخص'}): ${e.message}',
      );
    } on FormatException catch (e, st) {
      LoggerService.error(
        'Invalid recent orders response',
        error: e,
        stackTrace: st,
      );
      throw Exception(e.message);
    } catch (e, st) {
      LoggerService.error(
        'Unexpected recent orders error',
        error: e,
        stackTrace: st,
      );
      throw Exception('خطا در پردازش سفارش‌های اخیر: $e');
    }
  }
}
