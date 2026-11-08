import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/supabase_service.dart';

class SmsRepository {
  final SupabaseClient _client;
  SmsRepository({SupabaseClient? client}) : _client = client ?? SupabaseService.client;

  Future<Map<String, dynamic>> getSettings() async {
    final row = await _client.from('sms_settings').select('*').eq('id', 1).single();
    return Map<String, dynamic>.from(row);
  }

  Future<Map<String, dynamic>> saveSettings(Map<String, dynamic> settings) async {
    final result = await _client.rpc('admin_save_sms_settings', params: settings);
    if (result is! Map) throw const FormatException('پاسخ ذخیره تنظیمات پیامک معتبر نیست.');
    return Map<String, dynamic>.from(result);
  }

  Future<List<Map<String, dynamic>>> getTemplates() async {
    final rows = await _client.from('sms_event_templates').select('*').order('event_key');
    return rows.map((row) => Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<void> updateTemplate(Map<String, dynamic> template) async {
    final key = (template['event_key'] ?? '').toString();
    await _client.from('sms_event_templates').update({
      'normal_message': (template['normal_message'] ?? '').toString(),
      'pattern_body_id': (template['pattern_body_id'] ?? '').toString(),
      'is_active': template['is_active'] == true,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('event_key', key);
  }

  Future<List<Map<String, dynamic>>> getCampaigns({int limit = 100}) async {
    final rows = await _client.from('sms_campaigns').select(
      'id,name,send_mode,status,scheduled_at,recipient_count,sent_count,delivered_count,failed_count,created_at,completed_at,cancelled_at',
    ).order('created_at', ascending: false).limit(limit);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<Map<String, dynamic>> cancelCampaign(String campaignId) async {
    final result = await _client.rpc('admin_cancel_sms_campaign', params: {
      'p_campaign_id': campaignId,
    });
    if (result is! Map) throw const FormatException('پاسخ لغو کمپین معتبر نیست.');
    return Map<String, dynamic>.from(result);
  }

  Future<String> queueTestSms({required String phone, required String message, required String bodyId, required List<String> patternArgs}) async {
    final result = await _client.rpc('admin_queue_test_sms', params: {
      'p_phone': phone.trim(),
      'p_message': message,
      'p_body_id': bodyId,
      'p_pattern_args': patternArgs,
    });
    if (result == null) throw const FormatException('شناسه پیام آزمایشی برنگشت.');
    return result.toString();
  }

  Future<Map<String, dynamic>> dispatch({int batchSize = 10}) async {
    final response = await _client.functions.invoke('sms-dispatch', body: {'batchSize': batchSize});
    if (response.status < 200 || response.status >= 300) {
      throw Exception('اجرای پردازشگر پیامک ناموفق بود (HTTP ${response.status}).');
    }
    if (response.data is Map) return Map<String, dynamic>.from(response.data as Map);
    return {'result': response.data};
  }

  Future<Map<String, dynamic>> getCampaignEffectiveness({int days = 90}) async {
    final end = DateTime.now().toUtc();
    final start = end.subtract(Duration(days: days));
    final result = await _client.rpc('admin_get_sms_campaign_effectiveness', params: {
      'p_start': start.toIso8601String(),
      'p_end': end.toIso8601String(),
    });
    if (result is! Map) throw const FormatException('گزارش اثربخشی کمپین معتبر نیست.');
    return Map<String, dynamic>.from(result);
  }

  Future<List<Map<String, dynamic>>> getStaff() async {
    final rows = await _client.from('sms_staff_recipients').select('*').order('created_at', ascending: false);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<void> saveStaff({String? id, required String name, required String phone, required String roleLabel, required List<String> orderTypes, required bool active}) async {
    final data = {
      'name': name.trim(),
      'phone': phone.trim(),
      'role_label': roleLabel.trim().isEmpty ? 'پرسنل' : roleLabel.trim(),
      'order_types': orderTypes,
      'is_active': active,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (id == null) {
      await _client.from('sms_staff_recipients').insert(data);
    } else {
      await _client.from('sms_staff_recipients').update(data).eq('id', id);
    }
  }

  Future<void> setStaffActive(String id, bool active) async {
    await _client.from('sms_staff_recipients').update({'is_active': active, 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
  }

  Future<List<Map<String, dynamic>>> getOutbox({int limit = 200}) async {
    final rows = await _client.from('sms_outbox').select(
      'id,event_key,recipient_phone,send_mode,normal_message,pattern_body_id,status,attempts,max_attempts,last_error,provider_message_id,delivery_status,delivered_at,delivery_code,delivery_error,created_at,sent_at,related_order_id,related_ticket_id,campaign_id',
    ).order('created_at', ascending: false).limit(limit);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getAttemptLogs({int limit = 300}) async {
    final rows = await _client.from('sms_attempt_logs').select('*').order('created_at', ascending: false).limit(limit);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getDeliveryStats({int limit = 400}) async {
    final rows = await _client.from('sms_delivery_stats_view').select('*').order('report_date', ascending: true).limit(limit);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList(growable: false);
  }
}
