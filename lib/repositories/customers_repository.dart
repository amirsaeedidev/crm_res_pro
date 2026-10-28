import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/logger_service.dart';
import '../core/services/supabase_service.dart';
import '../models/user_model.dart';

class CustomersRepository {
  final SupabaseClient _client;
  CustomersRepository({SupabaseClient? client}) : _client = client ?? SupabaseService.client;

  Future<List<UserModel>> getCustomers({
    int page = 1,
    int pageSize = 20,
    String? searchQuery,
    String? statusFilter,
    bool? marketingOptInFilter,
  }) async {
    if (page < 1 || pageSize < 1) throw ArgumentError('page and pageSize must be positive');
    try {
      var query = _client.from('profiles').select('id,email,first_name,last_name,phone,avatar_url,role,status,marketing_sms_opt_in,created_at').eq('role', 'customer');
      final search = searchQuery?.trim();
      if (search != null && search.isNotEmpty) {
        final safe = search.replaceAll('\\', '\\\\').replaceAll(',', r'\,').replaceAll('%', r'\%').replaceAll('_', r'\_');
        query = query.or('first_name.ilike.%$safe%,last_name.ilike.%$safe%,email.ilike.%$safe%,phone.ilike.%$safe%');
      }
      if (statusFilter != null && statusFilter != 'all') query = query.eq('status', statusFilter);
      if (marketingOptInFilter != null) query = query.eq('marketing_sms_opt_in', marketingOptInFilter);
      final rows = await query.order('created_at', ascending: false).range((page - 1) * pageSize, page * pageSize - 1);
      return rows.map((row) => UserModel.fromJson(Map<String, dynamic>.from(row))).toList();
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch customers from public.profiles failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'دریافت مشتریان'));
    }
  }


  Future<({List<UserModel> customers, int totalCount})> getCustomersWithPurchaseMetrics({
    int page = 1,
    int pageSize = 20,
    String? searchQuery,
    String statusFilter = 'all',
    bool? marketingOptInFilter,
    int? minOrders,
    int? maxOrders,
    double? minSpend,
    double? maxSpend,
    String lastVisitFilter = 'all',
    String sortBy = 'recent',
  }) async {
    if (page < 1 || pageSize < 1) {
      throw ArgumentError('page and pageSize must be positive');
    }
    DateTime? lastVisitSince;
    if (lastVisitFilter == '7d') {
      lastVisitSince = DateTime.now().toUtc().subtract(const Duration(days: 7));
    } else if (lastVisitFilter == '30d') {
      lastVisitSince = DateTime.now().toUtc().subtract(const Duration(days: 30));
    } else if (lastVisitFilter == '90d') {
      lastVisitSince = DateTime.now().toUtc().subtract(const Duration(days: 90));
    }
    try {
      final response = await _client.rpc('get_customer_purchase_metrics', params: {
        'p_search': searchQuery,
        'p_status_filter': statusFilter,
        'p_marketing_filter': marketingOptInFilter,
        'p_min_orders': minOrders,
        'p_max_orders': maxOrders,
        'p_min_spend': minSpend,
        'p_max_spend': maxSpend,
        'p_last_visit_since': lastVisitSince?.toIso8601String(),
        'p_never_visited': lastVisitFilter == 'never',
        'p_sort_by': sortBy,
        'p_page': page,
        'p_page_size': pageSize,
      });
      final payload = Map<String, dynamic>.from(response as Map);
      final rows = (payload['customers'] as List<dynamic>? ?? const []);
      return (
        customers: rows.map((row) => UserModel.fromJson(Map<String, dynamic>.from(row as Map))).toList(growable: false),
        totalCount: (payload['total_count'] as num?)?.toInt() ?? 0,
      );
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch customers with purchase metrics failed', error: e, stackTrace: st);
      if (e.code == 'PGRST202' || e.code == '42883') {
        throw Exception('فیلترهای خرید مشتریان آماده نیستند؛ مهاجرت 026_customer_purchase_filters.sql را اعمال کنید.');
      }
      throw Exception(_friendlyError(e, 'دریافت و فیلتر مشتریان'));
    }
  }

  Future<UserModel> getCustomerById(String id) async {
    try {
      final row = await _client.from('profiles').select('id,email,first_name,last_name,phone,avatar_url,role,status,marketing_sms_opt_in,created_at').eq('id', id).eq('role', 'customer').single();
      return UserModel.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch customer detail failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'دریافت مشتری'));
    }
  }

  Future<List<Map<String, dynamic>>> getCustomerAddresses(String userId) async {
    try {
      final rows = await _client.from('addresses')
          .select('id,user_id,title,recipient_name,phone,address_line,postal_code,is_default,created_at,updated_at')
          .eq('user_id', userId).order('is_default', ascending: false).order('created_at', ascending: false);
      return rows.map((row) => Map<String, dynamic>.from(row)).toList(growable: false);
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch customer addresses failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'دریافت آدرس‌های مشتری'));
    }
  }

  Future<Map<String, dynamic>?> getCustomerWallet(String userId) async {
    try {
      final row = await _client.from('loyalty_wallets')
          .select('id,user_identifier,total_points,created_at,updated_at')
          .eq('user_identifier', userId).maybeSingle();
      return row == null ? null : Map<String, dynamic>.from(row);
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch customer wallet failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'دریافت کیف امتیاز مشتری'));
    }
  }

  Future<List<Map<String, dynamic>>> getCustomerWalletTransactions(String userId) async {
    try {
      final wallet = await getCustomerWallet(userId);
      if (wallet == null) return const [];
      final rows = await _client.from('loyalty_transactions')
          .select('id,wallet_id,order_id,points,transaction_type,description,created_at')
          .eq('wallet_id', wallet['id']).order('created_at', ascending: false).limit(100);
      return rows.map((row) => Map<String, dynamic>.from(row)).toList(growable: false);
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch loyalty transactions failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'دریافت گردش کیف امتیاز'));
    }
  }

  Future<int> adjustCustomerPoints({required String userId, required int pointsDelta, required String description}) async {
    try {
      final result = await _client.rpc('admin_adjust_loyalty_points', params: {
        'p_user_id': userId, 'p_points': pointsDelta, 'p_description': description.trim(),
      });
      if (result is num) return result.toInt();
      throw const FormatException('خروجی تابع اصلاح امتیاز نامعتبر است.');
    } on PostgrestException catch (e, st) {
      LoggerService.error('Adjust customer points failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'اصلاح امتیاز مشتری'));
    }
  }

  Future<void> updateCustomer(String id, Map<String, dynamic> data) async {
    final allowed = <String, dynamic>{};
    for (final key in ['first_name','last_name','phone','status','marketing_sms_opt_in']) {
      if (data.containsKey(key)) allowed[key] = data[key];
    }
    allowed['updated_at'] = DateTime.now().toUtc().toIso8601String();
    if (allowed.isEmpty) return;
    if (allowed['status'] != null && !{'active','blocked','inactive'}.contains(allowed['status'])) {
      throw ArgumentError.value(allowed['status'], 'status');
    }
    if (allowed['phone'] != null && (allowed['phone'] as String).trim().isEmpty) allowed['phone'] = null;
    if (allowed['marketing_sms_opt_in'] == true) {
      allowed['marketing_sms_opt_in_at'] = DateTime.now().toUtc().toIso8601String();
    } else if (allowed['marketing_sms_opt_in'] == false) {
      allowed['marketing_sms_opt_in_at'] = null;
    }
    try {
      final rows = await _client.from('profiles').update(allowed).eq('id', id).eq('role', 'customer').select('id');
      if (rows.isEmpty) throw Exception('مشتری پیدا نشد یا مجوز تغییر اطلاعات آن را ندارید.');
    } on PostgrestException catch (e, st) {
      LoggerService.error('Update customer failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'ویرایش اطلاعات مشتری'));
    }
  }

  Future<void> updateCustomerStatus(String id, String status) => updateCustomer(id, {'status': status});

  String _friendlyError(PostgrestException e, String action) {
    if (e.code == '42501' || e.code == 'PGRST301') return 'برای $action باید دسترسی مدیر داشته باشید.';
    if (e.code == 'PGRST205' || e.code == '42P01') return 'جدول یا ستون مورد نیاز در Supabase پیدا نشد: ${e.message}';
    if (e.code == 'PGRST202' || e.code == '42883') return 'تابع مدیریت کیف امتیاز نصب نشده است. Migration باشگاه مشتریان را بررسی کنید.';
    return 'خطا در $action: ${e.message}';
  }
}
