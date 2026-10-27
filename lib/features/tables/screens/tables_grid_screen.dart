import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_loading.dart';
import '../../../models/table_model.dart';
import '../../../providers/tables_provider.dart';
import '../../../shared/widgets/empty_widget.dart';
import '../../../shared/widgets/error_widget.dart' as app_error;

class TablesGridScreen extends StatefulWidget {
  const TablesGridScreen({super.key});

  @override
  State<TablesGridScreen> createState() => _TablesGridScreenState();
}

class _TablesGridScreenState extends State<TablesGridScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TablesProvider>().fetchTables();
    });
  }

  Color _getStatusColor(TableStatus status, BuildContext context) {
    switch (status) {
      case TableStatus.free:
        return AppColors.success;
      case TableStatus.occupied:
        return AppColors.error;
      case TableStatus.reserved:
        return AppColors.warning;
    }
  }

  IconData _getStatusIcon(TableStatus status) {
    switch (status) {
      case TableStatus.free:
        return Icons.check_circle_outline;
      case TableStatus.occupied:
        return Icons.event_busy_outlined;
      case TableStatus.reserved:
        return Icons.event_available_outlined;
    }
  }

  String _formatStatus(String status) {
    switch (status.toLowerCase()) {
      case 'free':
        return 'آزاد';
      case 'occupied':
        return 'اشغال';
      case 'reserved':
        return 'رزرو شده';
      case 'inactive':
        return 'غیرفعال';
      default:
        return 'وضعیت نامشخص';
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

  void _showTableActions(BuildContext context, TableModel table) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.large),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'میز ${_persianDigits(table.tableNumber)}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'وضعیت: ${_formatStatus(table.status.name)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _getStatusColor(table.status, context),
                  ),
                ),
                const Divider(height: AppSizes.xl),
                if (table.status == TableStatus.occupied &&
                    table.currentOrderId != null)
                  ListTile(
                    leading: const Icon(
                      Icons.receipt_long_outlined,
                      color: AppColors.info,
                    ),
                    title: const Text('مشاهده سفارش فعال'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/orders/details/${table.currentOrderId}');
                    },
                  ),
                ListTile(
                  leading: const Icon(
                    Icons.edit_outlined,
                    color: AppColors.info,
                  ),
                  title: const Text('ویرایش شماره و ظرفیت'),
                  onTap: () {
                    Navigator.pop(context);
                    _showTableForm(table: table);
                  },
                ),
                if (table.status == TableStatus.occupied)
                  ListTile(
                    leading: const Icon(
                      Icons.cleaning_services_outlined,
                      color: AppColors.success,
                    ),
                    title: const Text('آزاد کردن میز'),
                    subtitle: const Text(
                      'ابتدا مطمئن شوید سفارش فعالی به میز متصل نیست.',
                    ),
                    onTap: () async {
                      final provider = this.context.read<TablesProvider>();
                      final messenger = ScaffoldMessenger.of(this.context);
                      Navigator.pop(context);
                      final ok = await provider.markTableAsFree(table.id);
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? 'میز آزاد شد.'
                                : provider.error ?? 'تغییر وضعیت ناموفق بود.',
                          ),
                        ),
                      );
                    },
                  ),
                if (table.status == TableStatus.reserved)
                  ListTile(
                    leading: const Icon(
                      Icons.event_available_outlined,
                      color: AppColors.warning,
                    ),
                    title: const Text('مدیریت رزروهای میز'),
                    onTap: () {
                      Navigator.pop(context);
                      context.go('/reservations');
                    },
                  ),
                ListTile(
                  leading: Icon(
                    table.isActive
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: table.isActive ? AppColors.error : AppColors.success,
                  ),
                  title: Text(
                    table.isActive ? 'غیرفعال کردن میز' : 'فعال کردن میز',
                  ),
                  subtitle: const Text(
                    'غیرفعال‌سازی، میز را حذف فیزیکی نمی‌کند.',
                  ),
                  onTap: () async {
                    final provider = this.context.read<TablesProvider>();
                    final messenger = ScaffoldMessenger.of(this.context);
                    Navigator.pop(context);
                    final ok = await provider.setTableActive(
                      table.id,
                      !table.isActive,
                    );
                    if (!mounted) return;
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? 'وضعیت میز ذخیره شد.'
                              : provider.error ?? 'تغییر وضعیت ناموفق بود.',
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showTableForm({TableModel? table}) async {
    final tablesProvider = context.read<TablesProvider>();
    final numberController = TextEditingController(
      text: table?.tableNumber ?? '',
    );
    final capacityController = TextEditingController(
      text: table?.capacity.toString() ?? '2',
    );
    var isActive = table?.isActive ?? true;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(
            table == null ? 'افزودن میز' : 'ویرایش میز ${_persianDigits(table.tableNumber)}',
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: numberController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'شماره میز',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: capacityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'ظرفیت (نفر)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('میز فعال باشد'),
                  value: isActive,
                  onChanged: (value) => setDialogState(() => isActive = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () async {
                final number = int.tryParse(numberController.text.trim());
                final capacity = int.tryParse(capacityController.text.trim());
                if (number == null ||
                    number < 1 ||
                    capacity == null ||
                    capacity < 1) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('شماره میز و ظرفیت باید عدد مثبت باشند.'),
                    ),
                  );
                  return;
                }
                final ok = table == null
                    ? await tablesProvider.createTable(
                        tableNumber: number,
                        capacity: capacity,
                        isActive: isActive,
                      )
                    : await tablesProvider.updateTable(
                        id: table.id,
                        tableNumber: number,
                        capacity: capacity,
                        isActive: isActive,
                      );
                if (!dialogContext.mounted) return;
                if (ok) {
                  Navigator.pop(dialogContext, true);
                } else {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text(
                        tablesProvider.error ?? 'ذخیره میز ناموفق بود.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );
    numberController.dispose();
    capacityController.dispose();
    if (result == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('اطلاعات میز ذخیره شد.')));
    }
  }

  Widget _buildCountBadge({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.sm,
        vertical: AppSizes.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppRadius.circular),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSizes.xs),
          Text(
            _persianDigits(count),
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: AppSizes.xs),
          Text(label, style: TextStyle(color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Consumer<TablesProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.tables.isEmpty) {
            return const Center(child: AppLoading());
          }

          if (provider.error != null && provider.tables.isEmpty) {
            return app_error.AppErrorWidget(
              message: provider.error!,
              onRetry: () => provider.fetchTables(),
            );
          }

          final freeCount = provider.tables
              .where((t) => t.status == TableStatus.free)
              .length;
          final occupiedCount = provider.tables
              .where((t) => t.status == TableStatus.occupied)
              .length;
          final reservedCount = provider.tables
              .where((t) => t.status == TableStatus.reserved)
              .length;

          return Padding(
            padding: const EdgeInsets.all(AppSizes.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'مدیریت میزها',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => _showTableForm(),
                      icon: const Icon(Icons.add),
                      label: const Text('افزودن میز'),
                    ),
                    IconButton(
                      tooltip: 'به‌روزرسانی',
                      onPressed: provider.fetchTables,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: AppSizes.sm),
                Wrap(
                  spacing: AppSizes.sm,
                  runSpacing: AppSizes.sm,
                  children: [
                    _buildCountBadge(
                      label: 'میز آزاد',
                      count: freeCount,
                      color: AppColors.success,
                      icon: Icons.check_circle_outline,
                    ),
                    _buildCountBadge(
                      label: 'میز اشغال',
                      count: occupiedCount,
                      color: AppColors.error,
                      icon: Icons.event_busy_outlined,
                    ),
                    _buildCountBadge(
                      label: 'میز رزروشده',
                      count: reservedCount,
                      color: AppColors.warning,
                      icon: Icons.event_available_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: AppSizes.lg),
                Expanded(
                  child: provider.tables.isEmpty
                      ? const EmptyWidget(
                          title: 'هنوز میزی ثبت نشده است',
                          message:
                              'برای شروع از دکمه «افزودن میز» استفاده کنید.',
                          icon: Icons.table_restaurant_outlined,
                        )
                      : GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 200,
                                childAspectRatio: 0.88,
                                crossAxisSpacing: AppSizes.md,
                                mainAxisSpacing: AppSizes.md,
                              ),
                          itemCount: provider.tables.length,
                          itemBuilder: (context, index) {
                            final table = provider.tables[index];
                            final statusColor = table.isActive
                                ? _getStatusColor(table.status, context)
                                : AppColors.getSecondaryText(context);

                            return AppCard(
                              padding: EdgeInsets.zero,
                              onTap: () => _showTableActions(context, table),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(
                                      color: statusColor,
                                      width: 5,
                                    ),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSizes.md),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'میز',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      color: AppColors.getSecondaryText(context),
                                                    ),
                                              ),
                                              const SizedBox(width: AppSizes.xs),
                                              Text(
                                                _persianDigits(table.tableNumber),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleLarge
                                                    ?.copyWith(
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                              ),
                                            ],
                                          ),
                                          Icon(
                                            Icons.table_restaurant,
                                            color: statusColor.withValues(
                                              alpha: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Spacer(),
                                      Text(
                                        '${_persianDigits(table.capacity)} نفر',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: AppColors.getSecondaryText(
                                                context,
                                              ),
                                            ),
                                      ),
                                      const SizedBox(height: AppSizes.sm),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSizes.sm,
                                          vertical: AppSizes.sm,
                                        ),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(alpha: 0.09),
                                          borderRadius: AppRadius.mediumAll,
                                          border: Border.all(
                                            color: statusColor.withValues(alpha: 0.22),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'وضعیت میز',
                                              style: Theme.of(context).textTheme.labelSmall
                                                  ?.copyWith(
                                                color: AppColors.getSecondaryText(context),
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Row(
                                              children: [
                                                Icon(
                                                  table.isActive
                                                      ? _getStatusIcon(table.status)
                                                      : Icons.visibility_off_outlined,
                                                  size: 16,
                                                  color: statusColor,
                                                ),
                                                const SizedBox(width: AppSizes.xs),
                                                Expanded(
                                                  child: Text(
                                                    _formatStatus(
                                                      table.isActive
                                                          ? table.status.name
                                                          : 'inactive',
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: statusColor,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (table.status ==
                                              TableStatus.occupied &&
                                          table.currentOrderId != null) ...[
                                        const SizedBox(height: AppSizes.sm),
                                        Text(
                                          'سفارش فعال به این میز متصل است',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
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
