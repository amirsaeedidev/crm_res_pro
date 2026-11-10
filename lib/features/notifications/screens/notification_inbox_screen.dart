import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../../../providers/notifications_provider.dart';

String _formatNotificationDate(DateTime value) {
  final local = value.toLocal();
  final date = Jalali.fromDateTime(local);
  const digits = '۰۱۲۳۴۵۶۷۸۹';
  final raw = '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}  ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return raw.replaceAllMapped(RegExp(r'[0-9]'), (match) => digits[int.parse(match.group(0)!) ]);
}

class NotificationInboxScreen extends StatelessWidget {
  const NotificationInboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Consumer<NotificationsProvider>(
        builder: (context, provider, _) {
          final notifications = provider.notifications;
          final theme = Theme.of(context);
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'صندوق اعلان‌ها',
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text('${notifications.length} اعلان'),
                    const SizedBox(width: 8),
                    if (provider.unreadCount > 0)
                      TextButton.icon(
                        onPressed: provider.markAllAsRead,
                        icon: const HugeIcon(icon: HugeIcons.strokeRoundedCheckmarkCircle02, size: 18),
                        label: const Text('خواندن همه'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: provider.isLoading && notifications.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : notifications.isEmpty
                          ? const Center(child: Text('هنوز اعلانی دریافت نشده است.'))
                          : ListView.separated(
                              itemCount: notifications.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = notifications[index];
                                final itemColor = item.isRead
                                    ? theme.colorScheme.onSurfaceVariant
                                    : theme.colorScheme.primary;
                                return Opacity(
                                  opacity: item.isRead ? 0.52 : 1,
                                  child: Card(
                                    elevation: 0,
                                    color: item.isRead
                                        ? theme.colorScheme.surfaceContainerLowest
                                        : theme.colorScheme.surfaceContainerLow,
                                    child: ListTile(
                                      leading: HugeIcon(
                                        icon: switch (item.type) {
                                          NotificationType.newOrder => HugeIcons.strokeRoundedShoppingCart01,
                                          NotificationType.newReservation => HugeIcons.strokeRoundedCalendarCheckIn01,
                                          NotificationType.newCustomer => HugeIcons.strokeRoundedUserGroup,
                                          NotificationType.newTicket => HugeIcons.strokeRoundedHeadset,
                                          NotificationType.unknown => HugeIcons.strokeRoundedNotification01,
                                        },
                                        color: itemColor,
                                        size: 24,
                                      ),
                                      title: Text(
                                        item.title,
                                        style: TextStyle(
                                          fontWeight: item.isRead ? FontWeight.normal : FontWeight.bold,
                                        ),
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          '${item.description}\n${_formatNotificationDate(item.timestamp)}',
                                          maxLines: 4,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      isThreeLine: true,
                                      trailing: item.isRead
                                          ? const HugeIcon(icon: HugeIcons.strokeRoundedCheckmarkCircle02, size: 20)
                                          : TextButton(
                                              onPressed: () => provider.markAsRead(item.id),
                                              child: const Text('خوانده شد'),
                                            ),
                                      onTap: item.isRead ? null : () => provider.markAsRead(item.id),
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
