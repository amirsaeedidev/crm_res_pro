import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import '../../../core/services/supabase_service.dart';

class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  late Future<List<Map<String, dynamic>>> _logs;

  @override
  void initState() {
    super.initState();
    _logs = _loadLogs();
  }

  Future<List<Map<String, dynamic>>> _loadLogs() async {
    final rows = await SupabaseService.client
        .from('admin_activity_logs')
        .select('id, table_name, record_id, operation, actor_id, created_at')
        .order('created_at', ascending: false)
        .limit(500);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void _refresh() => setState(() => _logs = _loadLogs());

  String _operationLabel(String operation) => switch (operation) {
    'INSERT' => 'ایجاد',
    'UPDATE' => 'ویرایش',
    'DELETE' => 'حذف',
    _ => operation,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('ثبت فعالیت‌ها', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold))),
                IconButton(onPressed: _refresh, tooltip: 'بروزرسانی', icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh)),
              ],
            ),
            Text('تاریخچه تغییرات ثبت‌شده در بخش‌های متصل به گزارش فعالیت.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _logs,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  if (snapshot.hasError) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const HugeIcon(icon: HugeIcons.strokeRoundedAlert02, size: 42),
                    const SizedBox(height: 8),
                    const Text('دریافت گزارش فعالیت ناموفق بود.'),
                    TextButton(onPressed: _refresh, child: const Text('تلاش مجدد')),
                    const SizedBox(height: 8),
                    Text('ابتدا اسکریپت SQL مربوط به ثبت فعالیت را در Supabase اجرا کنید.', style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                  ]));
                  final logs = snapshot.data ?? [];
                  if (logs.isEmpty) return const Center(child: Text('هنوز فعالیتی ثبت نشده است.'));
                  return ListView.separated(
                    itemCount: logs.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      final operation = (log['operation'] ?? '').toString();
                      final createdAt = DateTime.tryParse((log['created_at'] ?? '').toString())?.toLocal();
                      final dateLabel = createdAt == null ? '—' : DateFormat('yyyy/MM/dd  HH:mm').format(createdAt);
                      return ListTile(
                        leading: HugeIcon(
                          icon: switch (operation) {
                            'INSERT' => HugeIcons.strokeRoundedAddCircle,
                            'UPDATE' => HugeIcons.strokeRoundedEdit02,
                            'DELETE' => HugeIcons.strokeRoundedDelete02,
                            _ => HugeIcons.strokeRoundedActivity01,
                          },
                          color: switch (operation) {
                            'INSERT' => Colors.green,
                            'UPDATE' => Colors.blue,
                            'DELETE' => Colors.red,
                            _ => theme.colorScheme.primary,
                          },
                        ),
                        title: Text('${_operationLabel(operation)} • ${log['table_name'] ?? '—'}'),
                        subtitle: Text('شناسه رکورد: ${log['record_id'] ?? '—'}\nکاربر: ${log['actor_id'] ?? 'سیستم'}\n$dateLabel'),
                        isThreeLine: true,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
