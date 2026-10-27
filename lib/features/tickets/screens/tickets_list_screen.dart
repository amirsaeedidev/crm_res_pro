import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../providers/tickets_provider.dart';

class TicketsListScreen extends StatefulWidget {
  const TicketsListScreen({super.key});

  @override
  State<TicketsListScreen> createState() => _TicketsListScreenState();
}

class _TicketsListScreenState extends State<TicketsListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<TicketsProvider>().fetchTickets();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'open':
      case 'received':
        return 'باز';
      case 'answered':
        return 'پاسخ داده‌شده';
      case 'closed':
        return 'بسته';
      case 'unread':
        return 'خوانده‌نشده';
      default:
        return 'نامشخص';
    }
  }

  Color _statusColor(String status, bool unread) {
    if (unread) return AppColors.error;
    switch (status) {
      case 'open':
      case 'received':
        return AppColors.warning;
      case 'answered':
        return AppColors.success;
      case 'closed':
        return AppColors.getSecondaryText(context);
      default:
        return AppColors.primary;
    }
  }

  String _persianDigits(Object? value) {
    const latin = '0123456789';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    var result = value?.toString() ?? '';
    for (var i = 0; i < latin.length; i++) {
      result = result.replaceAll(latin[i], persian[i]);
    }
    return result;
  }

  String _formatDate(DateTime value) {
    final date = value.toLocal();
    final formatted =
        '${date.year}/${date.month.toString().padLeft(2, '0')}/'
        '${date.day.toString().padLeft(2, '0')}  '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
    return _persianDigits(formatted);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSizes.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'مدیریت تیکت‌ها',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              Consumer<TicketsProvider>(
                builder: (context, provider, _) => IconButton(
                  onPressed: provider.isLoading ? null : provider.fetchTickets,
                  tooltip: 'به‌روزرسانی فهرست',
                  icon: provider.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Consumer<TicketsProvider>(
            builder: (context, provider, _) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = AppSizes.sm;
                  final columns = constraints.maxWidth >= 1050
                      ? 4
                      : constraints.maxWidth >= 560
                          ? 2
                          : 1;
                  final cardWidth =
                      (constraints.maxWidth - spacing * (columns - 1)) /
                          columns;

                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      _countCard(
                        width: cardWidth,
                        title: 'کل تیکت‌ها',
                        value: provider.counts['total'] ?? 0,
                        icon: Icons.inbox_outlined,
                        color: AppColors.primary,
                      ),
                      _countCard(
                        width: cardWidth,
                        title: 'تیکت‌های باز',
                        value: provider.counts['received'] ?? 0,
                        icon: Icons.mark_email_unread_outlined,
                        color: AppColors.warning,
                      ),
                      _countCard(
                        width: cardWidth,
                        title: 'خوانده‌نشده',
                        value: provider.counts['unread'] ?? 0,
                        icon: Icons.markunread_outlined,
                        color: AppColors.error,
                      ),
                      _countCard(
                        width: cardWidth,
                        title: 'پاسخ‌داده‌شده',
                        value: provider.counts['answered'] ?? 0,
                        icon: Icons.mark_email_read_outlined,
                        color: AppColors.success,
                      ),
                    ],
                  );
                },
              );
            },
          ),
          const SizedBox(height: AppSizes.md),
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'جست‌وجو در عنوان تیکت',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'پاک کردن جست‌وجو',
                onPressed: () {
                  _searchController.clear();
                  context.read<TicketsProvider>().setSearch('');
                },
                icon: const Icon(Icons.clear),
              ),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (value) =>
                context.read<TicketsProvider>().setSearch(value),
          ),
          const SizedBox(height: AppSizes.md),
          Consumer<TicketsProvider>(
            builder: (context, provider, _) => DropdownButtonFormField<String>(
              initialValue: provider.status,
              decoration: const InputDecoration(
                labelText: 'فیلتر وضعیت تیکت',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('همه تیکت‌ها')),
                DropdownMenuItem(value: 'received', child: Text('تیکت‌های باز')),
                DropdownMenuItem(value: 'unread', child: Text('خوانده‌نشده')),
                DropdownMenuItem(value: 'answered', child: Text('پاسخ داده‌شده')),
                DropdownMenuItem(value: 'closed', child: Text('بسته‌شده')),
              ],
              onChanged: provider.isLoading
                  ? null
                  : (value) {
                      if (value != null) provider.setStatus(value);
                    },
            ),
          ),
          const SizedBox(height: AppSizes.md),
          Expanded(
            child: Consumer<TicketsProvider>(
              builder: (context, provider, _) {
                if (provider.isLoading && provider.tickets.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (provider.error != null && provider.tickets.isEmpty) {
                  return _error(provider.error!, provider.fetchTickets);
                }

                if (provider.tickets.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox_outlined, size: 48),
                        SizedBox(height: AppSizes.md),
                        Text('برای این فیلتر تیکتی ثبت نشده است.'),
                      ],
                    ),
                  );
                }

                return Column(
                  children: [
                    if (provider.isLoading) const LinearProgressIndicator(),
                    Expanded(
                      child: ListView.separated(
                        itemCount: provider.tickets.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSizes.sm),
                        itemBuilder: (context, index) {
                          final ticket = provider.tickets[index];
                          final statusColor =
                              _statusColor(ticket.status, ticket.isUnread);
                          final customer = ticket.customerName.trim().isNotEmpty
                              ? ticket.customerName
                              : ticket.customerEmail;

                          return Card(
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => context.push('/tickets/${ticket.id}'),
                              child: Padding(
                                padding: const EdgeInsets.all(AppSizes.sm),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CircleAvatar(
                                      backgroundColor:
                                          statusColor.withValues(alpha: 0.12),
                                      child: Icon(
                                        Icons.support_agent,
                                        color: statusColor,
                                      ),
                                    ),
                                    const SizedBox(width: AppSizes.sm),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            ticket.subject,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                          const SizedBox(height: AppSizes.xs),
                                          Text(
                                            customer.isEmpty
                                                ? 'نام مشتری ثبت نشده است'
                                                : customer,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (ticket.customerPhone.isNotEmpty)
                                            Text(
                                              _persianDigits(ticket.customerPhone),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: AppColors
                                                        .getSecondaryText(context),
                                                  ),
                                            ),
                                          const SizedBox(height: AppSizes.xs),
                                          Text(
                                            _formatDate(ticket.createdAt),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: AppColors
                                                      .getSecondaryText(context),
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: AppSizes.sm),
                                    ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 112),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Chip(
                                            visualDensity:
                                                VisualDensity.compact,
                                            label: Text(
                                              _statusLabel(ticket.status),
                                            ),
                                            side: BorderSide.none,
                                            backgroundColor: statusColor
                                                .withValues(alpha: 0.12),
                                            labelStyle: TextStyle(
                                              color: statusColor,
                                              fontSize: 11,
                                            ),
                                          ),
                                          if (ticket.isUnread)
                                            const Text(
                                              'خوانده‌نشده',
                                              textAlign: TextAlign.end,
                                              style: TextStyle(
                                                color: AppColors.error,
                                                fontSize: 11,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: AppSizes.sm),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: 'صفحه قبلی',
                          onPressed: provider.currentPage > 1
                              ? () => provider.changePage(
                                    provider.currentPage - 1,
                                  )
                              : null,
                          icon: const Icon(Icons.chevron_right),
                        ),
                        Text(
                          'صفحه ${_persianDigits(provider.currentPage)} از '
                          '${_persianDigits(provider.totalPages)}',
                        ),
                        IconButton(
                          tooltip: 'صفحه بعدی',
                          onPressed: provider.currentPage < provider.totalPages
                              ? () => provider.changePage(
                                    provider.currentPage + 1,
                                  )
                              : null,
                          icon: const Icon(Icons.chevron_left),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _countCard({
    required double width,
    required String title,
    required int value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 66),
      padding: const EdgeInsets.all(AppSizes.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: AppSizes.xs),
          Text(
            _persianDigits(value),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _error(String error, Future<void> Function() retry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 42),
            const SizedBox(height: AppSizes.sm),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: AppSizes.md),
            FilledButton.icon(
              onPressed: retry,
              icon: const Icon(Icons.refresh),
              label: const Text('تلاش دوباره'),
            ),
          ],
        ),
      ),
    );
  }
}
