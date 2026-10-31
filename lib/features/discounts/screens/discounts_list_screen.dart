import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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

  String _formatDate(DateTime value) => _persianDigits(
        _dateFormatter.format(value.toLocal()),
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
    if (!discount.isActive) return ChipType.neutral;
    final now = DateTime.now();
    if (now.isBefore(discount.startDate)) return ChipType.neutral;
    if (now.isAfter(discount.endDate)) return ChipType.error;
    return ChipType.success;
  }

  String _getStatusText(DiscountModel discount) {
    if (!discount.isActive) return 'غیرفعال';
    final now = DateTime.now();
    if (now.isBefore(discount.startDate)) return 'زمان‌بندی‌شده';
    if (now.isAfter(discount.endDate)) return 'منقضی شده';
    return 'فعال';
  }

  String _usageLabel(DiscountModel discount) {
    final limit = discount.totalUsageLimit == null
        ? 'نامحدود'
        : _persianDigits(discount.totalUsageLimit.toString());
    return '${_persianDigits(discount.usedCount.toString())} / $limit';
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
                icon: Icons.add_rounded,
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
                    icon: Icons.discount_outlined,
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
                _buildHeaderText(context, 'مصرف', 1),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  discount.title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (discount.restrictedToCustomers)
                  Text(
                    'کد اختصاصی مشتریان انتخاب‌شده',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.primary),
                  ),
              ],
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
              discount.type == 'percentage' ? '${_persianDigits(discount.value)}٪' : '${_persianDigits(discount.value)} تومان',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_usageLabel(discount), style: Theme.of(context).textTheme.bodyMedium),
                if (discount.perUserUsageLimit != null)
                  Text(
                    'هر مشتری: ${_persianDigits(discount.perUserUsageLimit.toString())}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
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
                  icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                  onPressed: () {
                    context.push('/discounts/edit/${discount.id}');
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.error),
                  onPressed: () {
                    DeleteDialog.show(
                      context: context,
                      title: 'حذف تخفیف',
                      message: 'آیا از حذف تخفیف "${discount.title}" مطمئن هستید؟',
                      onDelete: () {
                        provider.deleteDiscount(discount.id);
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
                  CustomChip(
                    label: _getStatusText(discount),
                    type: _getStatusChipType(discount),
                  ),
                ],
              ),
              const Divider(height: AppSizes.md),
              _buildMobileRow(context, Icons.code, 'کد: ${discount.code}'),
              _buildMobileRow(
                context,
                Icons.percent,
                'مقدار: ${discount.type == 'percentage' ? '${_persianDigits(discount.value)}٪' : '${_persianDigits(discount.value)} تومان'}',
              ),
              _buildMobileRow(context, Icons.insights_outlined, 'مصرف کل: ${_usageLabel(discount)}'),
              if (discount.perUserUsageLimit != null)
                _buildMobileRow(context, Icons.person_outline, 'سقف هر مشتری: ${_persianDigits(discount.perUserUsageLimit.toString())} بار'),
              if (discount.restrictedToCustomers)
                _buildMobileRow(context, Icons.person_pin_circle_outlined, 'کد اختصاصی مشتریان انتخاب‌شده'),
              _buildMobileRow(context, Icons.calendar_today, 'پایان: ${_formatDate(discount.endDate)}'),
              const SizedBox(height: AppSizes.md),
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                      onPressed: () {
                        context.push('/discounts/edit/${discount.id}');
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.error),
                      onPressed: () {
                        DeleteDialog.show(
                          context: context,
                          title: 'حذف تخفیف',
                          message: 'آیا از حذف تخفیف "${discount.title}" مطمئن هستید؟',
                          onDelete: () {
                            provider.deleteDiscount(discount.id);
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

  Widget _buildMobileRow(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: AppSizes.sm),
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}