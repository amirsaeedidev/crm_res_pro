import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../providers/notifications_provider.dart';

import '../../../core/services/supabase_service.dart';
import '../../../repositories/notification_campaigns_repository.dart';

class NotificationsCenterScreen extends StatefulWidget {
  const NotificationsCenterScreen({super.key});

  @override
  State<NotificationsCenterScreen> createState() => _NotificationsCenterScreenState();
}

class _NotificationsCenterScreenState extends State<NotificationsCenterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  String _audience = 'all_customers';
  String _priority = 'normal';
  bool _sending = false;
  String? _resendingId;
  final _campaignRepository = NotificationCampaignsRepository();
  late Future<List<Map<String, dynamic>>> _sentHistory;

  @override
  void initState() {
    super.initState();
    _sentHistory = _loadSentHistory();
  }

  Future<List<Map<String, dynamic>>> _loadSentHistory() {
    return _campaignRepository.getHistory();
  }

  Future<void> _resend(Map<String, dynamic> campaign) async {
    if (_resendingId != null) return;
    setState(() => _resendingId = campaign['id']?.toString());
    try {
      final data = await _campaignRepository.resendCampaign(campaign);
      if (!mounted) return;
      setState(() => _sentHistory = _loadSentHistory());
      final retryData = data['sms_retry'] is Map ? Map<String, dynamic>.from(data['sms_retry'] as Map) : <String, dynamic>{};
      final channelData = data['channel_retry'] is Map ? Map<String, dynamic>.from(data['channel_retry'] as Map) : <String, dynamic>{};
      final count = (data['requeued_count'] as num?)?.toInt() ?? (retryData['requeued_count'] as num?)?.toInt() ?? (channelData['sent_count'] as num?)?.toInt() ?? (data['sent_count'] as num?)?.toInt() ?? (data['recipient_count'] as num?)?.toInt() ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ارسال مجدد ثبت شد. تعداد گیرندگان: $count')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ارسال مجدد ناموفق بود: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _resendingId = null);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate() || _sending) return;
    setState(() => _sending = true);
    try {
      final response = await SupabaseService.client.rpc(
        'admin_send_notification',
        params: {
          'p_title': _titleController.text.trim(),
          'p_body': _bodyController.text.trim(),
          'p_audience': _audience,
          'p_priority': _priority,
        },
      );
      final data = Map<String, dynamic>.from(response as Map);
      if (!mounted) return;
      final count = (data['recipient_count'] as num?)?.toInt() ?? 0;
      try {
        await _campaignRepository.recordManualNotification(
          title: _titleController.text.trim(),
          body: _bodyController.text.trim(),
          audience: _audience,
          priority: _priority,
          recipientCount: count,
        );
      } catch (historyError) {
        // The announcement has already been sent; do not report it as failed
        // solely because the separate audit/history write did not complete.
        debugPrint('Could not persist notification campaign history: $historyError');
      }
      if (!mounted) return;
      setState(() => _sentHistory = _loadSentHistory());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'اعلان ثبت شد، اما مخاطب فعالی در این گروه پیدا نشد.'
                : 'اعلان با موفقیت برای $count مخاطب ثبت شد.',
          ),
          backgroundColor: count == 0 ? Colors.orange : Colors.green,
        ),
      );
      if (count > 0) {
        _titleController.clear();
        _bodyController.clear();
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ارسال اعلان ناموفق بود: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('مدیریت اعلان‌ها', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    'مخاطبان اعلان و میزان اهمیت آن را مشخص کنید. ثبت اعلان‌ها از طریق تابع امن Supabase انجام می‌شود.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  Consumer<NotificationsProvider>(
                    builder: (context, provider, _) {
                      final notifications = provider.notifications;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text('صندوق اعلان‌ها',
                                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                  ),
                                  Text('${notifications.length} اعلان'),
                                  const SizedBox(width: 8),
                                  if (provider.unreadCount > 0)
                                    TextButton(
                                      onPressed: provider.markAllAsRead,
                                      child: const Text('خواندن همه'),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (provider.isLoading && notifications.isEmpty)
                                const Center(child: Padding(
                                  padding: EdgeInsets.all(20),
                                  child: CircularProgressIndicator(),
                                ))
                              else if (notifications.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Center(child: Text('هنوز اعلانی ثبت نشده است.')),
                                )
                              else
                                ...notifications.map((notification) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: HugeIcon(
                                    icon: switch (notification.type) {
                                      NotificationType.newOrder => HugeIcons.strokeRoundedShoppingCart01,
                                      NotificationType.newReservation => HugeIcons.strokeRoundedCalendarCheckIn01,
                                      NotificationType.newCustomer => HugeIcons.strokeRoundedUserGroup,
                                      NotificationType.newTicket => HugeIcons.strokeRoundedHeadset,
                                      NotificationType.unknown => HugeIcons.strokeRoundedNotification01,
                                    },
                                    color: notification.isRead
                                        ? theme.colorScheme.onSurfaceVariant
                                        : theme.colorScheme.primary,
                                  ),
                                  title: Text(notification.title,
                                    style: TextStyle(fontWeight: notification.isRead ? FontWeight.normal : FontWeight.bold)),
                                  subtitle: Text(notification.description),
                                  trailing: notification.isRead
                                      ? const HugeIcon(icon: HugeIcons.strokeRoundedCheckmarkCircle02)
                                      : TextButton(
                                          onPressed: () => provider.markAsRead(notification.id),
                                          child: const Text('خوانده شد'),
                                        ),
                                )),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('محتوای اعلان', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _titleController,
                            maxLength: 160,
                            decoration: const InputDecoration(labelText: 'عنوان اعلان', border: OutlineInputBorder(), prefixIcon: HugeIcon(icon: HugeIcons.strokeRoundedText)),
                            validator: (value) => value == null || value.trim().isEmpty ? 'عنوان اعلان را وارد کنید.' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _bodyController,
                            minLines: 4,
                            maxLines: 7,
                            maxLength: 4000,
                            decoration: const InputDecoration(labelText: 'متن اعلان', alignLabelWithHint: true, border: OutlineInputBorder(), prefixIcon: HugeIcon(icon: HugeIcons.strokeRoundedNote)),
                            validator: (value) => value == null || value.trim().isEmpty ? 'متن اعلان را وارد کنید.' : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('تعیین مخاطبان', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          RadioGroup<String>(
                            groupValue: _audience,
                            onChanged: (value) {
                              if (value != null) setState(() => _audience = value);
                            },
                            child: Column(
                              children: [
                                _audienceTile(
                                  value: 'all_customers',
                                  title: 'تمام مشتریان فعال',
                                  subtitle: 'ارسال اعلان به همه حساب‌های مشتری فعال',
                                  icon: HugeIcons.strokeRoundedUserGroup,
                                ),
                                _audienceTile(
                                  value: 'inactive_30d',
                                  title: 'مشتریان غیرفعال در ۳۰ روز اخیر',
                                  subtitle: 'مشتریانی که در ۳۰ روز گذشته سفارش غیرلغوشده نداشته‌اند',
                                  icon: HugeIcons.strokeRoundedUserRemove01,
                                ),
                                _audienceTile(
                                  value: 'admins',
                                  title: 'مدیران CRM',
                                  subtitle: 'ثبت اعلان در صندوق اعلان‌های مدیریتی',
                                  icon: HugeIcons.strokeRoundedShieldUser,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('سطح اهمیت اعلان', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          RadioGroup<String>(
                            groupValue: _priority,
                            onChanged: (value) {
                              if (value != null) setState(() => _priority = value);
                            },
                            child: Column(
                              children: [
                                RadioListTile<String>(
                                  value: 'normal',
                                  title: const Text('عادی'),
                                  subtitle: const Text('برای اطلاع‌رسانی‌های روزمره'),
                                  secondary: const HugeIcon(icon: HugeIcons.strokeRoundedNotification01, color: Colors.blueGrey),
                                  contentPadding: EdgeInsets.zero,
                                ),
                                RadioListTile<String>(
                                  value: 'high',
                                  title: const Text('مهم'),
                                  subtitle: const Text('برای اطلاعیه‌هایی که باید بیشتر دیده شوند'),
                                  secondary: const HugeIcon(icon: HugeIcons.strokeRoundedAlert02, color: Colors.orange),
                                  contentPadding: EdgeInsets.zero,
                                ),
                                RadioListTile<String>(
                                  value: 'urgent',
                                  title: const Text('فوری'),
                                  subtitle: const Text('برای هشدارهای ضروری و زمان‌حساس'),
                                  secondary: const HugeIcon(icon: HugeIcons.strokeRoundedAlert02, color: Colors.red),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton.icon(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const HugeIcon(icon: HugeIcons.strokeRoundedArrowUpRight01),
                      label: Text(_sending ? 'در حال ثبت...' : 'ثبت و ارسال اعلان'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'تاریخچه اعلان‌های ارسال‌شده',
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                              IconButton(
                                tooltip: 'بروزرسانی تاریخچه',
                                onPressed: () => setState(() => _sentHistory = _loadSentHistory()),
                                icon: const Icon(Icons.refresh),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          FutureBuilder<List<Map<String, dynamic>>>(
                            future: _sentHistory,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }
                              if (snapshot.hasError) {
                                return Text(
                                  'تاریخچه در دسترس نیست. Migration شماره 040 را در Supabase اجرا کنید.\n${snapshot.error}',
                                  style: TextStyle(color: theme.colorScheme.error),
                                );
                              }
                              final rows = snapshot.data ?? const <Map<String, dynamic>>[];
                              if (rows.isEmpty) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(child: Text('هنوز اعلانی ارسال نشده است.')),
                                );
                              }
                              return Column(
                                children: rows.map((row) {
                                  final channels = (row['delivery_channels'] as List? ?? const [])
                                      .map((value) => value.toString())
                                      .map((value) => switch (value) {
                                            'banner' => 'بنر',
                                            'notification' => 'اعلان',
                                            'sms' => 'پیامک',
                                            _ => value,
                                          })
                                      .join('، ');
                                  final createdAt = DateTime.tryParse((row['created_at'] ?? '').toString())?.toLocal();
                                  final dateLabel = createdAt == null
                                      ? '—'
                                      : createdAt.toString().substring(0, 16);
                                  final audience = switch ((row['audience'] ?? '').toString()) {
                                    'admins' => 'مدیران',
                                    'all_customers' => 'همه مشتریان',
                                    'inactive_30d' => 'مشتریان غیرفعال',
                                    'targeted_discount' => 'مشتریان هدف تخفیف',
                                    _ => '—',
                                  };
                                  final channelResults = row['channel_results'] is Map
                                      ? Map<String, dynamic>.from(row['channel_results'] as Map)
                                      : <String, dynamic>{};
                                  final hasFailedDiscountChannel = channelResults.values.any((value) {
                                    if (value is! Map) return false;
                                    final channelStatus = (value['status'] ?? '').toString();
                                    return channelStatus == 'failed' || channelStatus == 'partial';
                                  });
                                  final isResendable = (row['campaign_type'] == 'manual' && (row['delivery_channels'] as List? ?? const []).contains('notification')) ||
                                      (row['campaign_type'] == 'discount' &&
                                          (row['discount_id']?.toString().isNotEmpty ?? false) &&
                                          hasFailedDiscountChannel);
                                  final status = switch ((row['status'] ?? '').toString()) {
                                    'completed' => 'تکمیل‌شده',
                                    'partial' => 'ارسال ناقص',
                                    'failed' => 'ناموفق',
                                    'queued' => 'در صف ارسال',
                                    'sending' => 'در حال ارسال',
                                    'cancelled' => 'لغوشده',
                                    _ => '—',
                                  };
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text((row['title'] ?? 'اعلان').toString()),
                                    subtitle: Text(
                                      '$status • ${row['sent_count'] ?? 0} ارسال از ${row['target_count'] ?? 0} هدف • $audience • $channels\n$dateLabel',
                                    ),
                                    isThreeLine: true,
                                    trailing: isResendable
                                        ? IconButton(
                                            tooltip: 'ارسال مجدد',
                                            onPressed: _resendingId == row['id'] ? null : () => _resend(row),
                                            icon: _resendingId == row['id']
                                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                                : const Icon(Icons.replay),
                                          )
                                        : const Icon(Icons.history),
                                  );
                                }).toList(),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _audienceTile({
    required String value,
    required String title,
    required String subtitle,
    required List<List<dynamic>> icon,
  }) {
    return RadioListTile<String>(
      value: value,
      title: Text(title),
      subtitle: Text(subtitle),
      secondary: HugeIcon(icon: icon),
      contentPadding: EdgeInsets.zero,
    );
  }
}
