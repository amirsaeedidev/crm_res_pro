import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/logger_service.dart';
import '../core/services/supabase_service.dart';
import '../models/loyalty_models.dart';

class LoyaltyRepository {
  final SupabaseClient _client;
  LoyaltyRepository({SupabaseClient? client}) : _client = client ?? SupabaseService.client;

  Future<List<LoyaltyWalletModel>> getWallets({String? search}) async {
    try {
      var query = _client.from('loyalty_wallets_view').select('*');
      final normalized = search?.trim();
      if (normalized != null && normalized.isNotEmpty) {
        final safe = normalized
            .replaceAll('\\', '\\\\')
            .replaceAll(',', r'\,')
            .replaceAll('%', r'\%')
            .replaceAll('_', r'\_');
        query = query.or('customer_name.ilike.%$safe%,customer_phone.ilike.%$safe%');
      }
      final rows = await query.order('total_points', ascending: false);
      return rows
          .map((row) => LoyaltyWalletModel.fromJson(Map<String, dynamic>.from(row)))
          .toList(growable: false);
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch loyalty wallets failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'دریافت کیف امتیاز مشتریان'));
    }
  }

  Future<List<LoyaltyTransactionModel>> getTransactions(String walletId, {int limit = 50}) async {
    try {
      final rows = await _client
          .from('loyalty_transactions')
          .select('*')
          .eq('wallet_id', walletId)
          .order('created_at', ascending: false)
          .limit(limit.clamp(1, 100).toInt());
      return rows
          .map((row) => LoyaltyTransactionModel.fromJson(Map<String, dynamic>.from(row)))
          .toList(growable: false);
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch loyalty transactions failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'دریافت گردش امتیاز'));
    }
  }

  /// Uses an atomic admin-only RPC; never modifies the wallet and ledger in
  /// separate client requests. Run manual SQL migration 003 before use.
  Future<int> adjustPoints({
    required String userId,
    required int pointsDelta,
    required String description,
  }) async {
    if (pointsDelta == 0) throw ArgumentError('تغییر امتیاز نمی‌تواند صفر باشد.');
    if (description.trim().isEmpty) throw ArgumentError('دلیل تغییر امتیاز الزامی است.');
    try {
      final result = await _client.rpc(
        'admin_adjust_loyalty_points',
        params: {
          'p_user_id': userId,
          'p_points': pointsDelta,
          'p_description': description.trim(),
        },
      );
      if (result is num) return result.toInt();
      throw const FormatException('پاسخ RPC تغییر امتیاز معتبر نیست.');
    } on PostgrestException catch (e, st) {
      LoggerService.error('Adjust loyalty points failed', error: e, stackTrace: st);
      if (e.code == 'PGRST202' || e.code == '42883') {
        throw Exception('تابع تنظیم امتیاز هنوز در Supabase نصب نشده است. فایل supabase/manual/003_admin_adjust_loyalty_points.sql را اجرا کنید.');
      }
      throw Exception(_friendlyError(e, 'تغییر امتیاز مشتری'));
    }
  }


  Future<Map<String, dynamic>> quoteDiscount({
    required String userId,
    required int points,
    required int orderAmountToman,
  }) async {
    try {
      final result = await _client.rpc('admin_quote_loyalty_discount', params: {
        'p_user_id': userId,
        'p_points': points,
        'p_order_amount_toman': orderAmountToman,
      });
      if (result is Map) return Map<String, dynamic>.from(result);
      throw const FormatException('پاسخ محاسبه تخفیف معتبر نیست.');
    } on PostgrestException catch (e, st) {
      LoggerService.error('Quote loyalty discount failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'محاسبه تخفیف امتیازی'));
    }
  }

  String _friendlyError(PostgrestException e, String action) {
    if (e.code == '42501' || e.code == 'PGRST301') return 'برای $action باید با حساب مدیر فعال وارد شوید.';
    if (e.code == '23503') return 'رکورد وابسته در دیتابیس پیدا نشد.';
    return 'خطا در $action: ${e.message}';
  }
}
