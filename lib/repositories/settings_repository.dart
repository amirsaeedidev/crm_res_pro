import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/supabase_service.dart';

/// Reads and writes the single restaurant_settings row.
/// The table is provisioned by supabase/manual/004_restaurant_settings.sql.
class SettingsRepository {
  final SupabaseClient _client;

  SettingsRepository({SupabaseClient? client})
      : _client = client ?? SupabaseService.client;

  Future<Map<String, dynamic>> getSettings() async {
    final row = await _client
        .from('restaurant_settings')
        .select('*')
        .eq('id', 'restaurant')
        .maybeSingle();
    return row == null ? <String, dynamic>{} : Map<String, dynamic>.from(row);
  }

  Future<Map<String, dynamic>> saveSettings({
    required String companyName,
    required String companyPhone,
    required String companyAddress,
    required double minDeliveryAmount,
    required double fixedDeliveryFee,
  }) async {
    _validateAmounts(minDeliveryAmount, fixedDeliveryFee);
    final currentUserId = _client.auth.currentUser?.id;
    final rows = await _client
        .from('restaurant_settings')
        .update({
          'company_name': companyName.trim(),
          'company_phone': companyPhone.trim(),
          'company_address': companyAddress.trim(),
          'min_delivery_amount': minDeliveryAmount,
          'fixed_delivery_fee': fixedDeliveryFee,
          'updated_by': currentUserId,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', 'restaurant')
        .select('*');
    if (rows.isEmpty) {
      throw Exception('تنظیمات فروشگاه یافت نشد یا مجوز ویرایش ندارید. اسکریپت 004 را اجرا و با حساب مدیر وارد شوید.');
    }
    return Map<String, dynamic>.from(rows.first);
  }

  Future<Map<String, dynamic>> updateColors({
    required int primaryColor,
    required int secondaryColor,
  }) async {
    final rows = await _client
        .from('restaurant_settings')
        .update({
          'primary_color': primaryColor,
          'secondary_color': secondaryColor,
          'updated_by': _client.auth.currentUser?.id,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', 'restaurant')
        .select('*');
    if (rows.isEmpty) {
      throw Exception('تنظیمات فروشگاه یافت نشد یا مجوز ویرایش ندارید. اسکریپت 004 را اجرا و با حساب مدیر وارد شوید.');
    }
    return Map<String, dynamic>.from(rows.first);
  }

  void _validateAmounts(double minimum, double fee) {
    if (!minimum.isFinite || minimum < 0) {
      throw ArgumentError.value(minimum, 'minDeliveryAmount', 'مبلغ باید عدد مثبت یا صفر باشد.');
    }
    if (!fee.isFinite || fee < 0) {
      throw ArgumentError.value(fee, 'fixedDeliveryFee', 'مبلغ باید عدد مثبت یا صفر باشد.');
    }
  }
}
