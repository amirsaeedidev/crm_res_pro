import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/services/supabase_service.dart';
import '../core/services/logger_service.dart';
import '../models/discount_model.dart';

class DiscountsRepository {
  final SupabaseClient _client;
  DiscountsRepository({SupabaseClient? client}) : _client = client ?? SupabaseService.client;

  Future<List<DiscountModel>> getDiscounts({int page = 1, int pageSize = 15, String? searchQuery}) async {
    if (page < 1 || pageSize < 1) throw ArgumentError('page and pageSize must be positive');
    try {
      var query = _client.from('discounts').select('*');
      final search = searchQuery?.trim();
      if (search != null && search.isNotEmpty) query = query.or('title.ilike.%${_safeFilter(search)}%,code.ilike.%${_safeFilter(search)}%');
      final rows = await query.order('created_at', ascending: false).range((page - 1) * pageSize, page * pageSize - 1);
      return rows.map((row) => DiscountModel.fromJson(Map<String, dynamic>.from(row))).toList();
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch discounts failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'دریافت تخفیف‌ها'));
    }
  }

  Future<DiscountModel> getDiscountById(String id) async {
    try {
      final row = await _client.from('discounts').select('*').eq('id', id).single();
      final targets = await _client.from('discount_customer_targets').select('phone_snapshot').eq('discount_id', id);
      final data = Map<String, dynamic>.from(row);
      data['target_phones'] = targets.map((target) => (target['phone_snapshot'] ?? '').toString()).where((phone) => phone.isNotEmpty).toList();
      return DiscountModel.fromJson(data);
    } on PostgrestException catch (e, st) {
      LoggerService.error('Fetch discount by ID failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'دریافت تخفیف'));
    }
  }

  Future<DiscountModel> createDiscount(Map<String, dynamic> data) async {
    try {
      final row = await _client.from('discounts').insert(_normalize(data)).select().single();
      final id = row['id'].toString();
      if (data.containsKey('target_phones') || data.containsKey('restricted_to_customers')) {
        await _syncTargetPhones(id, data['target_phones'], data['restricted_to_customers'] == true);
      }
      final result = Map<String, dynamic>.from(row);
      result['target_phones'] = _targetPhoneList(data['target_phones']);
      return DiscountModel.fromJson(result);
    } on PostgrestException catch (e, st) {
      LoggerService.error('Create discount failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'ثبت تخفیف'));
    }
  }

  Future<DiscountModel> updateDiscount(String id, Map<String, dynamic> data) async {
    try {
      final row = await _client.from('discounts').update(_normalize(data)).eq('id', id).select().single();
      if (data.containsKey('target_phones') || data.containsKey('restricted_to_customers')) {
        await _syncTargetPhones(id, data['target_phones'], data['restricted_to_customers'] == true);
      }
      final result = Map<String, dynamic>.from(row);
      result['target_phones'] = _targetPhoneList(data['target_phones']);
      return DiscountModel.fromJson(result);
    } on PostgrestException catch (e, st) {
      LoggerService.error('Update discount failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'ویرایش تخفیف'));
    }
  }

  Future<void> deleteDiscount(String id) async {
    try { await _client.from('discounts').delete().eq('id', id); }
    on PostgrestException catch (e, st) {
      LoggerService.error('Delete discount failed', error: e, stackTrace: st);
      throw Exception(_friendlyError(e, 'حذف تخفیف'));
    }
  }

  Map<String, dynamic> _normalize(Map<String, dynamic> input) {
    final source = Map<String, dynamic>.from(input);
    final out = <String, dynamic>{};
    void copyAlias(String from, String to) { if (source.containsKey(from)) out[to] = source[from]; }
    copyAlias('title','title'); copyAlias('code','code'); copyAlias('description','description');
    copyAlias('discount_value','discount_value');
    if (source.containsKey('value')) out['discount_value'] = source['value'];
    if (source.containsKey('discount_type') || source.containsKey('type')) {
      final rawType = (source['discount_type'] ?? source['type'] ?? 'percent').toString();
      out['discount_type'] = rawType == 'percentage' ? 'percent' : (rawType == 'fixed_amount' ? 'fixed' : rawType);
    }
    if (source.containsKey('min_order_amount')) out['min_order_amount'] = source['min_order_amount'];
    if (source.containsKey('min_purchase_amount')) out['min_order_amount'] = source['min_purchase_amount'];
    copyAlias('max_discount_amount','max_discount_amount');
    copyAlias('restricted_to_customers','restricted_to_customers');
    copyAlias('per_user_usage_limit','per_user_usage_limit');
    if (source.containsKey('usage_limit')) out['usage_limit'] = source['usage_limit'];
    if (source.containsKey('total_usage_limit')) out['usage_limit'] = source['total_usage_limit'];
    copyAlias('used_count','used_count'); copyAlias('is_active','is_active');
    if (source.containsKey('start_date')) out['starts_at'] = source['start_date'];
    if (source.containsKey('starts_at')) out['starts_at'] = source['starts_at'];
    if (source.containsKey('end_date')) out['expires_at'] = source['end_date'];
    if (source.containsKey('expires_at')) out['expires_at'] = source['expires_at'];
    copyAlias('updated_at','updated_at');
    if (source.containsKey('restricted_to_customers')) out['restricted_to_customers'] = source['restricted_to_customers'] == true;
    out.remove('target_phones');
    out.removeWhere((key, value) => value == null && !{'max_discount_amount','usage_limit','per_user_usage_limit','starts_at','expires_at','description'}.contains(key));
    return out;
  }

  List<String> _targetPhoneList(dynamic raw) => raw is List
      ? raw.map((value) => value.toString().trim()).where((value) => value.isNotEmpty).toSet().toList()
      : const <String>[];

  String _phoneKey(String input) {
    // Accept both Latin and Persian/Arabic numerals copied from customer lists.
    final normalized = String.fromCharCodes(input.runes.map((code) {
      if (code >= 0x06F0 && code <= 0x06F9) return code - 0x06F0 + 0x30;
      if (code >= 0x0660 && code <= 0x0669) return code - 0x0660 + 0x30;
      return code;
    }));
    var digits = normalized.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0098')) digits = digits.substring(2);
    if (digits.startsWith('0') && digits.length >= 10) digits = '98${digits.substring(1)}';
    if (!digits.startsWith('98') && digits.length == 10) digits = '98$digits';
    return digits;
  }

  Future<void> _syncTargetPhones(String discountId, dynamic rawPhones, bool restricted) async {
    final phones = _targetPhoneList(rawPhones);
    if (restricted && phones.isEmpty) {
      throw Exception('برای تخفیف محدود به مشتریان، حداقل یک شماره تلفن وارد کنید.');
    }

    List<Map<String, dynamic>> targets = [];
    if (restricted) {
      final requested = phones.map(_phoneKey).where((v) => v.isNotEmpty).toSet();
      final profiles = await _client.from('profiles').select('id,phone').eq('role', 'customer').not('phone', 'is', null).limit(5000);
      final profileMap = <String, Map<String, dynamic>>{};
      for (final row in profiles) {
        final phone = (row['phone'] ?? '').toString();
        final key = _phoneKey(phone);
        if (key.isNotEmpty) profileMap.putIfAbsent(key, () => Map<String, dynamic>.from(row));
      }
      final unknown = requested.where((phone) => !profileMap.containsKey(phone)).toList();
      if (unknown.isNotEmpty) {
        throw Exception('این شماره‌ها در پروفایل مشتریان ثبت نشده‌اند: ${unknown.join(', ')}');
      }
      targets = requested.map((key) {
        final row = profileMap[key]!;
        return <String, dynamic>{
          'discount_id': discountId,
          'user_id': row['id'],
          'phone_snapshot': (row['phone'] ?? '').toString(),
        };
      }).toList();
    }

    // Resolve all numbers before deleting existing targets, so a typo won't clear a working restriction.
    await _client.from('discount_customer_targets').delete().eq('discount_id', discountId);
    if (targets.isNotEmpty) await _client.from('discount_customer_targets').insert(targets);
  }

  String _safeFilter(String value) => value.replaceAll('\\', '\\\\').replaceAll(',', r'\,').replaceAll('%', r'\%').replaceAll('_', r'\_');
  String _friendlyError(PostgrestException e, String action) {
    if (e.code == '42501' || e.code == 'PGRST301') return 'مجوز لازم برای $action ندارید. نشست ورود و نقش مدیر را بررسی کنید.';
    if (e.code == '23505') return 'کد تخفیف تکراری است؛ کد دیگری وارد کنید.';
    if (e.code == '23514') return 'مقادیر تخفیف با محدودیت‌های دیتابیس سازگار نیستند.';
    return 'خطا در $action: ${e.message}';
  }
}
