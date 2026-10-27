import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_loading.dart';
import '../../../core/widgets/custom_chip.dart';
import '../../../providers/customers_provider.dart';

class CustomersListScreen extends StatefulWidget {
  const CustomersListScreen({super.key});

  @override
  State<CustomersListScreen> createState() => _CustomersListScreenState();
}

class _CustomersListScreenState extends State<CustomersListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CustomersProvider>().fetchCustomers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  String _statusLabel(String status) => switch (status) {
        'active' => 'فعال',
        'inactive' => 'غیرفعال',
        'blocked' => 'مسدود',
        _ => 'نامشخص',
      };

  ChipType _statusType(String status) => switch (status) {
        'active' => ChipType.success,
        'inactive' => ChipType.warning,
        'blocked' => ChipType.error,
        _ => ChipType.neutral,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSizes.md),
      child: Consumer<CustomersProvider>(
        builder: (context, provider, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: AppRadius.mediumAll,
                  ),
                  child: const Icon(
                    Icons.people_alt_outlined,
                    color: AppColors.primary,
                    size: 26,
                  ),
                ),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مدیریت مشتریان',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${_persianDigits(provider.totalItems)} مشتری ثبت‌شده',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.getSecondaryText(context),
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'به‌روزرسانی فهرست',
                  onPressed: provider.isLoading ? null : provider.fetchCustomers,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'جست‌وجو و فیلتر',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: AppSizes.sm),
                  TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onChanged: provider.setSearchQuery,
                    decoration: InputDecoration(
                      hintText: 'جست‌وجو بر اساس نام، تلفن یا ایمیل',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'پاک کردن جست‌وجو',
                              onPressed: () {
                                _searchController.clear();
                                provider.setSearchQuery('');
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                  const SizedBox(height: AppSizes.md),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final fieldWidth = constraints.maxWidth < 540
                          ? constraints.maxWidth
                          : 220.0;
                      return Wrap(
                        spacing: AppSizes.sm,
                        runSpacing: AppSizes.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: fieldWidth,
                            child: DropdownButtonFormField<String>(
                              initialValue: provider.statusFilter,
                              decoration: const InputDecoration(
                                labelText: 'وضعیت مشتری',
                                prefixIcon: Icon(Icons.manage_accounts_outlined),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'all', child: Text('همه وضعیت‌ها')),
                                DropdownMenuItem(value: 'active', child: Text('فعال')),
                                DropdownMenuItem(value: 'inactive', child: Text('غیرفعال')),
                                DropdownMenuItem(value: 'blocked', child: Text('مسدود')),
                              ],
                              onChanged: (value) {
                                if (value != null) provider.setStatusFilter(value);
                              },
                            ),
                          ),
                          SizedBox(
                            width: fieldWidth,
                            child: DropdownButtonFormField<String>(
                              initialValue: provider.marketingFilter,
                              decoration: const InputDecoration(
                                labelText: 'رضایت پیامک تبلیغاتی',
                                prefixIcon: Icon(Icons.sms_outlined),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'all', child: Text('همه مشتریان')),
                                DropdownMenuItem(value: 'opted_in', child: Text('رضایت داده‌اند')),
                                DropdownMenuItem(value: 'opted_out', child: Text('رضایت نداده‌اند')),
                              ],
                              onChanged: (value) {
                                if (value != null) provider.setMarketingFilter(value);
                              },
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: provider.isLoading ? null : provider.fetchCustomers,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('به‌روزرسانی'),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSizes.md),
            if (provider.error != null && provider.customers.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_outlined, size: 44),
                      const SizedBox(height: AppSizes.sm),
                      Text(provider.error!, textAlign: TextAlign.center),
                      const SizedBox(height: AppSizes.md),
                      FilledButton.icon(
                        onPressed: provider.fetchCustomers,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('تلاش دوباره'),
                      ),
                    ],
                  ),
                ),
              )
            else if (provider.isLoading && provider.customers.isEmpty)
              const Expanded(child: Center(child: AppLoading()))
            else if (provider.customers.isEmpty)
              const Expanded(
                child: Center(
                  child: Text('مشتری‌ای مطابق جست‌وجو پیدا نشد.'),
                ),
              )
            else ...[
              Expanded(
                child: ListView.separated(
                  itemCount: provider.customers.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSizes.sm),
                  itemBuilder: (context, index) {
                    final customer = provider.customers[index];
                    return AppCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.10),
                              borderRadius: AppRadius.mediumAll,
                            ),
                            child: Text(
                              customer.fullName.isEmpty
                                  ? '?'
                                  : customer.fullName.characters.first,
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSizes.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  customer.fullName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                if ((customer.phone ?? '').isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    _persianDigits(customer.phone),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                      color: AppColors.getSecondaryText(context),
                                    ),
                                  ),
                                ],
                                if (customer.email.isNotEmpty) ...[
                                  Text(
                                    customer.email,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                      color: AppColors.getSecondaryText(context),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: AppSizes.sm),
                                Wrap(
                                  spacing: AppSizes.xs,
                                  runSpacing: AppSizes.xs,
                                  children: [
                                    CustomChip(
                                      label: _statusLabel(customer.status),
                                      type: _statusType(customer.status),
                                    ),
                                    CustomChip(
                                      label: customer.marketingSmsOptIn
                                          ? 'رضایت پیامک دارد'
                                          : 'بدون رضایت پیامک',
                                      type: customer.marketingSmsOptIn
                                          ? ChipType.success
                                          : ChipType.neutral,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'عملیات مشتری',
                            onSelected: (value) async {
                              if (value == 'details') {
                                context.push('/customers/details/${customer.id}');
                                return;
                              }
                              final ok = await provider.updateCustomerStatus(
                                customer.id,
                                value,
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ok
                                        ? 'وضعیت مشتری ذخیره شد.'
                                        : provider.error ?? 'تغییر وضعیت ناموفق بود.',
                                  ),
                                ),
                              );
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'details',
                                child: ListTile(
                                  dense: true,
                                  leading: Icon(Icons.open_in_new_rounded),
                                  title: Text('جزئیات مشتری'),
                                ),
                              ),
                              if (customer.status != 'active')
                                const PopupMenuItem(
                                  value: 'active',
                                  child: ListTile(
                                    dense: true,
                                    leading: Icon(Icons.check_circle_outline),
                                    title: Text('فعال کردن'),
                                  ),
                                ),
                              if (customer.status != 'inactive')
                                const PopupMenuItem(
                                  value: 'inactive',
                                  child: ListTile(
                                    dense: true,
                                    leading: Icon(Icons.pause_circle_outline),
                                    title: Text('غیرفعال کردن'),
                                  ),
                                ),
                              if (customer.status != 'blocked')
                                const PopupMenuItem(
                                  value: 'blocked',
                                  child: ListTile(
                                    dense: true,
                                    leading: Icon(Icons.block_outlined, color: Colors.red),
                                    title: Text('مسدود کردن'),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSizes.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'صفحه قبلی',
                    onPressed: provider.currentPage > 1
                        ? () => provider.changePage(provider.currentPage - 1)
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
                        ? () => provider.changePage(provider.currentPage + 1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
