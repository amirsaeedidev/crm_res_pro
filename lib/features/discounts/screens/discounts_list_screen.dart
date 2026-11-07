import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_loading.dart';
import '../../../core/widgets/app_search.dart';
import '../../../core/widgets/custom_chip.dart';
import '../../../models/discount_model.dart';
import '../../../providers/discounts_provider.dart';
import '../../../repositories/discounts_repository.dart';
import '../../../shared/dialogs/delete_dialog.dart';
import '../../../shared/widgets/empty_widget.dart';
import '../../../shared/widgets/error_widget.dart' as app_error;
import '../../../shared/widgets/pagination_widget.dart';

class DiscountsListScreen extends StatefulWidget {
  const DiscountsListScreen({super.key});

  @override
  State<DiscountsListScreen> createState() => _DiscountsListScreenState();
}

class _DiscountsListScreenState extends State<DiscountsListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final DateFormat _dateFormatter = DateFormat('yyyy-MM-dd');

  String _persianDigits(Object? value) {
    const latin = '0123456789';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    var result = value?.toString() ?? '';
    for (var i = 0; i < latin.length; i++) {
      result = result.replaceAll(latin[i], persian[i]);
    }
    return result;
  }

  String _formatThousands(Object? value) {
    final raw = value?.toString() ?? '0';
    final integer = raw.split('.').first.replaceAll(',', '');
    final grouped = integer.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return _persianDigits(grouped);
  }

  String _formatDate(DateTime value) => _persianDigits(
        _dateFormatter.format(value),
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DiscountsProvider>().fetchDiscounts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  ChipType _getStatusChipType(DiscountModel discount) {
    switch (discount.serverStatus) {
      case 'inactive': return ChipType.neutral;
      case 'scheduled': return ChipType.neutral;
      case 'exhausted': return ChipType.error;
      case 'expired': return ChipType.error;
      default: return ChipType.success;
    }
  }

  String _getStatusText(DiscountModel discount) {
    switch (discount.serverStatus) {
      case 'inactive': return 'غیرفعال';
      case 'scheduled': return 'زمان‌بندی‌شده';
      case 'exhausted': return 'تمام‌شده';
      case 'expired': return 'منقضی شده';
      default: return 'فعال';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSizes.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'مدیریت تخفیف‌ها',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.getPrimaryText(context),
                      fontWeight: FontWeight.bold,
                    ),
              ),
              AppButton(
                label: 'افزودن تخفیف جدید',
                iconWidget: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01, size: 18),
                width: 200,
                onPressed: () {
                  context.push('/discounts/add');
                },
              ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),

          // Search Bar
          AppSearch(
            controller: _searchController,
            onChanged: (value) {
              context.read<DiscountsProvider>().setSearchQuery(value);
            },
          ),
          const SizedBox(height: AppSizes.lg),

          // Content Area
          Expanded(
            child: Consumer<DiscountsProvider>(
              builder: (context, provider, child) {
                if (provider.isLoading && provider.discounts.isEmpty) {
                  return const Center(child: AppLoading());
                }

                if (provider.error != null && provider.discounts.isEmpty) {
                  return app_error.AppErrorWidget(
                    message: provider.error!,
                    onRetry: () => provider.fetchDiscounts(),
                  );
                }

                if (provider.discounts.isEmpty) {
                  return const EmptyWidget(
                    title: 'تخفیفی یافت نشد',
                    message: 'هیچ تخفیفی مطابق با جستجوی شما یافت نشد.',
                    icon: Icons.filter_alt_outlined,
                  );
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth > 600) {
                      return _buildDesktopTable(context, provider);
                    }
                    return _buildMobileList(context, provider);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showRedemptionHistory(BuildContext context, DiscountModel discount) async {
    try {
      final rows = await context.read<DiscountsRepository>().getDiscountRedemptions(discount.id);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('سوابق مصرف ${discount.code}'),
          content: SizedBox(
            width: 560,
            height: 420,
            child: rows.isEmpty
                ? const Center(child: Text('هنوز مصرفی برای این کد ثبت نشده است.'))
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final released = row['status'] == 'released';
                      final date = DateTime.tryParse((row['redeemed_at'] ?? '').toString());
                      final customerName = (row['customer_name'] ?? '').toString();
                      final amount = (row['discount_amount'] as num?)?.round() ?? 0;
                      return ListTile(
                        title: Text(customerName.isEmpty ? 'مشتری' : customerName),
                        subtitle: Text('${row['phone'] ?? '—'} • سفارش ${row['order_code'] ?? '—'}\n${date == null ? '—' : DateFormat('yyyy/MM/dd HH:mm').format(date.toLocal())}'),
                        isThreeLine: true,
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${NumberFormat('#,###').format(amount)} تومان'),
                            Text(released ? 'ظرفیت آزادشده' : 'مصرف‌شده', style: TextStyle(color: released ? Colors.grey : Colors.green, fontSize: 11)),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('بستن'))],
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('دریافت سوابق مصرف ناموفق بود: $error')));
    }
  }

  Widget _buildDesktopTable(BuildContext context, DiscountsProvider provider) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.md),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            ),
            child: Row(
              children: [
                _buildHeaderText(context, 'عنوان', 2),
                _buildHeaderText(context, 'کد تخفیف', 1),
                _buildHeaderText(context, 'نوع', 1),
                _buildHeaderText(context, 'مقدار', 1),
                _buildHeaderText(context, 'تاریخ پایان', 1),
                _buildHeaderText(context, 'وضعیت', 1),
                _buildHeaderText(context, 'عملیات', 1),
              ],
            ),
          ),
          // Table Rows
          Expanded(
            child: ListView.separated(
              itemCount: provider.discounts.length,
              separatorBuilder: (context, index) => Divider(height: 1, color: Theme.of(context).dividerColor),
              itemBuilder: (context, index) {
                final discount = provider.discounts[index];
                return _buildDesktopRow(context, provider, discount);
              },
            ),
          ),
          if (provider.totalPages > 1)
            Padding(
              padding: const EdgeInsets.all(AppSizes.md),
              child: PaginationWidget(
                currentPage: provider.currentPage,
                totalPages: provider.totalPages,
                onPageChanged: (page) {
                  provider.changePage(page);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderText(BuildContext context, String text, int flex) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }

  Widget _buildDesktopRow(BuildContext context, DiscountsProvider provider, DiscountModel discount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.md),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              discount.title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              discount.code,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.primary,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              discount.type == 'percentage' ? 'درصدی' : 'مبلغی',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              discount.type == 'percentage' ? '${_persianDigits(discount.value)}٪' : '${_formatThousands(discount.value)} تومان',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              _formatDate(discount.endDate),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            flex: 1,
            child: CustomChip(
              label: _getStatusText(discount),
              type: _getStatusChipType(discount),
            ),
          ),
          Expanded(
            flex: 1,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'سوابق مصرف',
                  icon: const Icon(Icons.history, color: AppColors.primary),
                  onPressed: () => _showRedemptionHistory(context, discount),
                ),
                IconButton(
                  tooltip: discount.isActive ? 'غیرفعال کردن تخفیف' : 'فعال کردن تخفیف',
                  icon: Icon(
                    discount.isActive ? Icons.pause_circle_outline : Icons.play_circle_outline,
                    color: discount.isActive ? Colors.orange : Colors.green,
                  ),
                  onPressed: () async {
                    final ok = await provider.toggleDiscountStatus(discount.id, !discount.isActive);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(ok ? (discount.isActive ? 'تخفیف غیرفعال شد.' : 'تخفیف فعال شد.') : (provider.error ?? 'تغییر وضعیت تخفیف ناموفق بود.')),
                    ));
                  },
                ),

                IconButton(
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedEdit02, color: AppColors.primary),
                  onPressed: () {
                    context.push('/discounts/edit/${discount.id}');
                  },
                ),
                IconButton(
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01, color: AppColors.error),
                  onPressed: () {
                    DeleteDialog.show(
                      context: context,
                      title: 'حذف تخفیف',
                      message: 'آیا از حذف تخفیف "${discount.title}" مطمئن هستید؟',
                      onDelete: () async {
                        final deleted = await provider.deleteDiscount(discount.id);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(deleted ? 'تخفیف حذف شد.' : (provider.error ?? 'حذف تخفیف ناموفق بود؛ اگر سابقه مصرف دارد آن را غیرفعال کنید.')),
                        ));
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileList(BuildContext context, DiscountsProvider provider) {
    return ListView.separated(
      itemCount: provider.discounts.length,
      separatorBuilder: (context, index) => const SizedBox(height: AppSizes.md),
      itemBuilder: (context, index) {
        final discount = provider.discounts[index];
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    discount.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    tooltip: 'سوابق مصرف',
                    icon: const Icon(Icons.history, color: AppColors.primary),
                    onPressed: () => _showRedemptionHistory(context, discount),
                  ),
                  CustomChip(
                    label: _getStatusText(discount),
                    type: _getStatusChipType(discount),
                  ),
                ],
              ),
              const Divider(height: AppSizes.md),
              _buildMobileRow(context, const HugeIcon(icon: HugeIcons.strokeRoundedMessage01, size: 16), 'کد: ${discount.code}'),
              _buildMobileRow(
                context,
                const HugeIcon(icon: HugeIcons.strokeRoundedFilter, size: 16),
                'مقدار: ${discount.type == 'percentage' ? '${_persianDigits(discount.value)}٪' : '${_formatThousands(discount.value)} تومان'}',
              ),
              _buildMobileRow(context, const HugeIcon(icon: HugeIcons.strokeRoundedCalendar01, size: 16), 'پایان: ${_formatDate(discount.endDate)}'),
              const SizedBox(height: AppSizes.md),
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: discount.isActive ? 'غیرفعال کردن تخفیف' : 'فعال کردن تخفیف',
                      icon: Icon(
                        discount.isActive ? Icons.pause_circle_outline : Icons.play_circle_outline,
                        color: discount.isActive ? Colors.orange : Colors.green,
                      ),
                      onPressed: () async {
                        final ok = await provider.toggleDiscountStatus(discount.id, !discount.isActive);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(ok ? (discount.isActive ? 'تخفیف غیرفعال شد.' : 'تخفیف فعال شد.') : (provider.error ?? 'تغییر وضعیت تخفیف ناموفق بود.')),
                        ));
                      },
                    ),
                    IconButton(
                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedEdit02, color: AppColors.primary),
                      onPressed: () {
                        context.push('/discounts/edit/${discount.id}');
                      },
                    ),
                    IconButton(
                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01, color: AppColors.error),
                      onPressed: () {
                        DeleteDialog.show(
                          context: context,
                          title: 'حذف تخفیف',
                          message: 'آیا از حذف تخفیف "${discount.title}" مطمئن هستید؟',
                          onDelete: () async {
                            final deleted = await provider.deleteDiscount(discount.id);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(deleted ? 'تخفیف حذف شد.' : (provider.error ?? 'حذف تخفیف ناموفق بود؛ اگر سابقه مصرف دارد آن را غیرفعال کنید.')),
                            ));
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMobileRow(BuildContext context, Widget icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          IconTheme(data: IconThemeData(size: 16, color: Theme.of(context).colorScheme.secondary), child: icon),
          const SizedBox(width: AppSizes.sm),
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}