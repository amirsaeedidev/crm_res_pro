import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/services/supabase_service.dart';

class NotificationCampaignsRepository {
  final SupabaseClient _client;

  NotificationCampaignsRepository({SupabaseClient? client})
      : _client = client ?? SupabaseService.client;

  Future<List<Map<String, dynamic>>> getHistory({int limit = 100}) async {
    final rows = await _client
        .from('admin_notification_campaigns')
        .select(
          'id,campaign_type,title,body,audience,delivery_channels,status,'
          'target_count,sent_count,failed_count,channel_results,metadata,'
          'created_at,sent_at,source_campaign_id,discount_id,sms_campaign_id,request_key',
        )
        .order('created_at', ascending: false)
        .limit(limit);
    return rows
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<void> recordManualNotification({
    required String title,
    required String body,
    required String audience,
    required String priority,
    required int recipientCount,
    String? sourceCampaignId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('admin_notification_campaigns').insert({
      'campaign_type': 'manual',
      'title': title.trim(),
      'body': body.trim(),
      'audience': audience,
      'delivery_channels': ['notification'],
      'status': 'completed',
      'target_count': recipientCount,
      'sent_count': recipientCount,
      'failed_count': 0,
      'channel_results': {
        'notification': {
          'recipient_count': recipientCount,
          'priority': priority,
        },
      },
      'metadata': {'priority': priority},
      'source_campaign_id': sourceCampaignId,
      'sent_at': now,
      'updated_at': now,
    });
  }

  Future<Map<String, dynamic>> resendCampaign(
    Map<String, dynamic> campaign,
  ) async {
    final campaignType = campaign['campaign_type']?.toString();
    if (campaignType == 'discount') {
      final discountId = campaign['discount_id']?.toString();
      if (discountId == null || discountId.isEmpty) {
        throw ArgumentError('شناسه تخفیف برای ارسال مجدد موجود نیست.');
      }
      final channelResults = campaign['channel_results'] is Map
          ? Map<String, dynamic>.from(campaign['channel_results'] as Map)
          : <String, dynamic>{};
      final failedChannels = channelResults.entries
          .where((entry) {
            final value = entry.value is Map ? Map<String, dynamic>.from(entry.value as Map) : <String, dynamic>{};
            return value['status'] == 'failed' || value['status'] == 'partial';
          })
          .map((entry) => entry.key)
          .where((channel) => {'banner', 'notification', 'sms'}.contains(channel))
          .toSet();
      if (failedChannels.isEmpty) {
        throw StateError('در این کمپین کانال ناموفقی برای ارسال مجدد وجود ندارد.');
      }

      final result = <String, dynamic>{'success': true};
      if (failedChannels.remove('sms')) {
        final smsResult = channelResults['sms'] is Map
            ? Map<String, dynamic>.from(channelResults['sms'] as Map)
            : <String, dynamic>{};
        final smsCampaignId = (campaign['sms_campaign_id'] ?? smsResult['sms_campaign_id'])?.toString();
        if (smsCampaignId == null || smsCampaignId.isEmpty) {
          throw StateError('شناسه کمپین پیامکی برای تلاش مجدد موجود نیست.');
        }
        final retry = await _client.rpc(
          'admin_retry_sms_campaign_failures',
          params: {'p_campaign_id': smsCampaignId},
        );
        if (retry is! Map) throw const FormatException('پاسخ تلاش مجدد پیامک معتبر نیست.');
        result['sms_retry'] = Map<String, dynamic>.from(retry);
      }

      if (failedChannels.isNotEmpty) {
        final metadata = campaign['metadata'] is Map
            ? Map<String, dynamic>.from(campaign['metadata'] as Map)
            : <String, dynamic>{};
        final audienceMode = (metadata['audience_mode'] ?? campaign['audience'] ?? 'all_customers').toString();
        final customerIds = (metadata['customer_ids'] as List? ?? const [])
            .map((value) => value.toString())
            .toList(growable: false);
        final response = await _client.rpc(
          'admin_dispatch_discount_delivery_v2',
          params: {
            'p_discount_id': discountId,
            'p_channels': failedChannels.toList(growable: false),
            'p_audience': audienceMode == 'targeted_discount' ? 'selected_customers' : audienceMode,
            'p_customer_ids': customerIds,
            'p_source_campaign_id': campaign['id'],
            'p_request_key': const Uuid().v4(),
          },
        );
        if (response is! Map) throw const FormatException('پاسخ ارسال مجدد تخفیف معتبر نیست.');
        result['channel_retry'] = Map<String, dynamic>.from(response);
      }
      return result;
    }

    if (campaignType != 'manual') {
      throw ArgumentError('نوع کمپین برای ارسال مجدد پشتیبانی نمی‌شود.');
    }
    final channels = (campaign['delivery_channels'] as List? ?? const [])
        .map((value) => value.toString())
        .toSet();
    if (!channels.contains('notification') || channels.length != 1) {
      throw ArgumentError('ارسال مجدد این نوع کمپین از مسیر اعلان پشتیبانی نمی‌شود.');
    }

    final metadata = campaign['metadata'] is Map
        ? Map<String, dynamic>.from(campaign['metadata'] as Map)
        : <String, dynamic>{};
    final priority = (metadata['priority'] ?? 'normal').toString();
    final response = await _client.rpc(
      'admin_send_notification',
      params: {
        'p_title': campaign['title'],
        'p_body': campaign['body'],
        'p_audience': campaign['audience'],
        'p_priority': priority,
      },
    );
    if (response is! Map) {
      throw const FormatException('پاسخ ارسال مجدد اعلان معتبر نیست.');
    }

    final count = (response['recipient_count'] as num?)?.toInt() ?? 0;
    await recordManualNotification(
      title: campaign['title'].toString(),
      body: campaign['body'].toString(),
      audience: campaign['audience'].toString(),
      priority: priority,
      recipientCount: count,
      sourceCampaignId: campaign['id']?.toString(),
    );
    return Map<String, dynamic>.from(response);
  }
}
