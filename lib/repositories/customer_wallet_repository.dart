import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/logger_service.dart';
import '../core/services/supabase_service.dart';
import '../models/customer_wallet_model.dart';

class CustomerWalletRepository {
  final SupabaseClient _client;
  CustomerWalletRepository({SupabaseClient? client}) : _client = client ?? SupabaseService.client;

  Future<List<CustomerWalletModel>> getWallets({String? search}) async {
    try {
      var query = _client.from('customer_wallets_view').select('*');
      final normalized = search?.trim();
      if (normalized != null && normalized.isNotEmpty) {
        final safe = normalized
            .replaceAll('\\', '\\\\')
            .replaceAll(',', r'\,')
            .replaceAll('(', r'\(')
            .replaceAll(')', r'\)')
            .replaceAll('%', r'\%')
            .replaceAll('_', r'\_');
        query = query.or('customer_name.ilike.%$safe%,customer_phone.ilike.%$safe%,email.ilike.%$safe%');
      }
      final rows = await query.order('updated_at', ascending: false).limit(250);
      return rows.map((row) => CustomerWalletModel.fromJson(Map<String, dynamic>.from(row))).toList(growable: false);
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch customer wallets failed', error: e, stackTrace: st);
      throw Exception(e.code == '42501' ? 'فقط مدیر فعال اجازه مشاهده کیف پول‌ها را دارد.' : 'دریافت کیف پول‌ها ناموفق بود: ${e.message}');
    }
  }

  Future<List<CustomerWalletTransactionModel>> getTransactions(String userId, {int limit = 50}) async {
    try {
      final rows = await _client.from('customer_wallet_transactions').select('*').eq('user_id', userId)
          .order('created_at', ascending: false).limit(limit.clamp(1, 100).toInt());
      return rows.map((row) => CustomerWalletTransactionModel.fromJson(Map<String, dynamic>.from(row))).toList(growable: false);
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch wallet transactions failed', error: e, stackTrace: st);
      throw Exception('دریافت گردش کیف پول ناموفق بود: ${e.message}');
    }
  }


  Future<List<Map<String, dynamic>>> getAllTransactions({int limit = 500}) async {
    try {
      final rows = await _client.from('customer_wallet_transactions').select('*')
          .order('created_at', ascending: false).limit(limit.clamp(1, 1000).toInt());
      return rows.map((row) => Map<String, dynamic>.from(row)).toList(growable: false);
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch global wallet ledger failed', error: e, stackTrace: st);
      throw Exception('دریافت دفتر کل کیف پول ناموفق بود: ${e.message}');
    }
  }

  Future<double> adjustBalance({required String userId, required double amountDelta, required String reason}) async {
    if (amountDelta == 0 || !amountDelta.isFinite) throw ArgumentError('مبلغ باید غیرصفر و معتبر باشد.');
    if (reason.trim().isEmpty) throw ArgumentError('دلیل تراکنش الزامی است.');
    try {
      final result = await _client.rpc('admin_adjust_customer_wallet', params: {
        'p_user_id': userId,
        'p_amount_delta': amountDelta,
        'p_reason': reason.trim(),
        'p_transaction_type': amountDelta > 0 ? 'top_up' : 'adjustment',
      });
      if (result is Map && result['balance'] is num) return (result['balance'] as num).toDouble();
      throw const FormatException('پاسخ سرور برای تغییر موجودی کیف پول معتبر نیست.');
    } on PostgrestException catch (e, st) {
      LoggerService.error('Adjust customer wallet failed', error: e, stackTrace: st);
      if (e.code == '42501') throw Exception('مجوز مدیر برای تغییر کیف پول لازم است.');
      if (e.code == '22023') throw Exception(e.message);
      throw Exception('تغییر موجودی کیف پول ناموفق بود: ${e.message}');
    }
  }
}
