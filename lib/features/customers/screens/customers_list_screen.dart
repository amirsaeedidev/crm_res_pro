import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
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
            Text('مدیریت مشتریان', style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: AppColors.getPrimaryText(context), fontWeight: FontWeight.bold)),
            const SizedBox(height: AppSizes.md),
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'جست‌وجو بر اساس نام، تلفن یا ایمیل',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () {
                  _searchController.clear();
                  provider.setSearchQuery('');
                }),
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => provider.setSearchQuery(value),
            ),
            const SizedBox(height: AppSizes.md),
            Wrap(
              spacing: AppSizes.sm,
              runSpacing: AppSizes.sm,
              children: [
                SizedBox(
                  width: 210,
                  child: DropdownButtonFormField<String>(
                    initialValue: provider.statusFilter,
                    decoration: const InputDecoration(labelText: 'وضعیت مشتری', border: OutlineInputBorder(), isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('همه وضعیت‌ها')),
                      DropdownMenuItem(value: 'active', child: Text('فعال')),
                      DropdownMenuItem(value: 'inactive', child: Text('غیرفعال')),
                      DropdownMenuItem(value: 'blocked', child: Text('مسدود')),
                    ],
                    onChanged: (value) { if (value != null) provider.setStatusFilter(value); },
                  ),
                ),
                SizedBox(
                  width: 230,
                  child: DropdownButtonFormField<String>(
                    initialValue: provider.marketingFilter,
                    decoration: const InputDecoration(labelText: 'رضایت پیامک تبلیغاتی', border: OutlineInputBorder(), isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('همه مشتریان')),
                      DropdownMenuItem(value: 'opted_in', child: Text('رضایت داده‌اند')),
                      DropdownMenuItem(value: 'opted_out', child: Text('رضایت نداده‌اند')),
                    ],
                    onChanged: (value) { if (value != null) provider.setMarketingFilter(value); },
                  ),
                ),
                Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: provider.fetchCustomers, icon: const Icon(Icons.refresh), label: const Text('به‌روزرسانی'))),
              ],
            ),
            const SizedBox(height: AppSizes.md),
            if (provider.error != null && provider.customers.isEmpty)
              Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(provider.error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(onPressed: provider.fetchCustomers, icon: const Icon(Icons.refresh), label: const Text('تلاش مجدد')),
              ])))
            else if (provider.isLoading && provider.customers.isEmpty)
              const Expanded(child: Center(child: AppLoading()))
            else if (provider.customers.isEmpty)
              const Expanded(child: Center(child: Text('مشتری‌ای مطابق جست‌وجو پیدا نشد.')))
            else ...[
              Expanded(
                child: ListView.separated(
                  itemCount: provider.customers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSizes.sm),
                  itemBuilder: (context, index) {
                    final customer = provider.customers[index];
                    return AppCard(child: Row(children: [
                      CircleAvatar(
                        backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                        child: Text(customer.fullName.isEmpty ? '?' : customer.fullName.characters.first,
                          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: AppSizes.md),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(customer.fullName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        if ((customer.phone ?? '').isNotEmpty) Text(customer.phone!, style: Theme.of(context).textTheme.bodySmall),
                        if (customer.email.isNotEmpty) Text(customer.email, style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, runSpacing: 4, children: [
                          CustomChip(label: _statusLabel(customer.status), type: _statusType(customer.status)),
                          CustomChip(label: customer.marketingSmsOptIn ? 'رضایت پیامک دارد' : 'بدون رضایت پیامک', type: customer.marketingSmsOptIn ? ChipType.success : ChipType.neutral),
                        ]),
                      ])),
                      PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'details') {
                            context.push('/customers/details/${customer.id}');
                            return;
                          }
                          final nextStatus = value;
                          final ok = await provider.updateCustomerStatus(customer.id, nextStatus);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(ok ? 'وضعیت مشتری ذخیره شد.' : provider.error ?? 'تغییر وضعیت ناموفق بود.'),
                          ));
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'details', child: Text('مشاهده جزئیات')),
                          if (customer.status != 'active') const PopupMenuItem(value: 'active', child: Text('فعال کردن')),
                          if (customer.status != 'inactive') const PopupMenuItem(value: 'inactive', child: Text('غیرفعال کردن')),
                          if (customer.status != 'blocked') const PopupMenuItem(value: 'blocked', child: Text('مسدود کردن')),
                        ],
                      ),
                    ]));
                  },
                ),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(onPressed: provider.currentPage > 1 ? () => provider.changePage(provider.currentPage - 1) : null, icon: const Icon(Icons.chevron_left)),
                Text('صفحه ${_persianDigits(provider.currentPage)} از ${_persianDigits(provider.totalPages)}'),
                IconButton(onPressed: provider.currentPage < provider.totalPages ? () => provider.changePage(provider.currentPage + 1) : null, icon: const Icon(Icons.chevron_right)),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
