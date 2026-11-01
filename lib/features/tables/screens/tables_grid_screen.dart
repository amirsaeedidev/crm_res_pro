import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_loading.dart';
import '../../../models/table_model.dart';
import '../../../providers/tables_provider.dart';
import '../../../shared/widgets/error_widget.dart' as app_error;

class TablesGridScreen extends StatefulWidget {
  const TablesGridScreen({super.key});

  @override
  State<TablesGridScreen> createState() => _TablesGridScreenState();
}

class _TablesGridScreenState extends State<TablesGridScreen> {
  TableStatus? _selectedStatus;
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

  Widget _getStatusIcon(TableStatus status) {
    switch (status) {
      case TableStatus.free:
        return const HugeIcon(icon: HugeIcons.strokeRoundedCheckmarkCircle02);
      case TableStatus.occupied:
        return const HugeIcon(icon: HugeIcons.strokeRoundedAlert02);
      case TableStatus.reserved:
        return const HugeIcon(icon: HugeIcons.strokeRoundedCalendar01);
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
                      HugeIcons.strokeRoundedReceipt,
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
                    HugeIcons.strokeRoundedEdit02,
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
                      HugeIcons.strokeRoundedRefresh,
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
                      HugeIcons.strokeRoundedCalendar01,
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
                        ? HugeIcons.strokeRoundedCancel01
                        : HugeIcons.strokeRoundedView,
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
    required Widget icon,
    required TableStatus status,
  }) {
    final selected = _selectedStatus == status;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.circular),
        onTap: () => setState(() {
          _selectedStatus = selected ? null : status;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.sm,
            vertical: AppSizes.xs,
          ),
          decoration: BoxDecoration(
            color: selected ? color : color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(AppRadius.circular),
            border: Border.all(color: color.withValues(alpha: selected ? 1 : 0.22)),
          ),
          child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: AppSizes.xs),
          Text(
            _persianDigits(count),
            style: TextStyle(color: selected ? Colors.white : color, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: AppSizes.xs),
          Text(label, style: TextStyle(color: selected ? Colors.white : color)),
        ],
          ),
        ),
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
          final filteredTables = _selectedStatus == null
              ? provider.tables
              : provider.tables.where((t) => t.status == _selectedStatus).toList();

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
                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01),
                      label: const Text('افزودن میز'),
                    ),
                    IconButton(
                      tooltip: 'به‌روزرسانی',
                      onPressed: provider.fetchTables,
                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh),
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
                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedCheckmarkCircle02),
                      status: TableStatus.free,
                    ),
                    _buildCountBadge(
                      label: 'میز اشغال',
                      count: occupiedCount,
                      color: AppColors.error,
                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedAlert02),
                      status: TableStatus.occupied,
                    ),
                    _buildCountBadge(
                      label: 'میز رزروشده',
                      count: reservedCount,
                      color: AppColors.warning,
                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedCalendar01),
                      status: TableStatus.reserved,
                    ),
                  ],
                ),
                const SizedBox(height: AppSizes.lg),
                Expanded(
                  child: provider.tables.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const HugeIcon(icon: HugeIcons.strokeRoundedCafe, size: 64),
                              const SizedBox(height: AppSizes.md),
                              const Text('هنوز میزی ثبت نشده است'),
                              const SizedBox(height: AppSizes.xs),
                              Text('برای شروع از دکمه «افزودن میز» استفاده کنید.', style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        )
                      : filteredTables.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const HugeIcon(icon: HugeIcons.strokeRoundedSearch01, size: 52),
                                  const SizedBox(height: AppSizes.md),
                                  Text('میزی با وضعیت انتخاب‌شده وجود ندارد.'),
                                  TextButton(onPressed: () => setState(() => _selectedStatus = null), child: const Text('نمایش همه میزها')),
                                ],
                              ),
                            )
                          : GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 200,
                                mainAxisExtent: 220,
                                crossAxisSpacing: AppSizes.md,
                                mainAxisSpacing: AppSizes.md,
                              ),
                          itemCount: filteredTables.length,
                          itemBuilder: (context, index) {
                            final table = filteredTables[index];
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
                                          HugeIcon(
                                            icon: HugeIcons.strokeRoundedCafe,
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
                                                table.isActive
                                                    ? _getStatusIcon(table.status)
                                                    : const HugeIcon(icon: HugeIcons.strokeRoundedCancel01),
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
