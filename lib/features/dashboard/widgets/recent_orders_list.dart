import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/custom_chip.dart';
import '../../../providers/dashboard_provider.dart';

class RecentOrdersList extends StatelessWidget {
  const RecentOrdersList({super.key});

  String _statusLabel(String status) => switch (status) {
        'pending' => 'در انتظار', 'confirmed' => 'تأییدشده',
        'preparing' => 'در حال آماده‌سازی', 'ready' => 'آماده',
        'out_for_delivery' => 'در مسیر ارسال', 'completed' => 'تکمیل‌شده',
        'cancelled' => 'لغوشده', _ => status,
      };

  ChipType _statusType(String status) => switch (status) {
        'completed' => ChipType.success,
        'cancelled' => ChipType.error,
        'pending' || 'confirmed' || 'preparing' || 'ready' || 'out_for_delivery' => ChipType.warning,
        _ => ChipType.neutral,
      };

  String _money(num amount) => amount.round().toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => ',');

  @override
  Widget build(BuildContext context) => Consumer<DashboardProvider>(
    builder: (context, provider, _) => AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('آخرین سفارش‌ها', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.getPrimaryText(context), fontWeight: FontWeight.bold)),
        TextButton(onPressed: () => context.go('/orders'), child: const Text('مشاهده همه')),
      ]),
      const SizedBox(height: AppSizes.md),
      if (provider.recentOrdersError != null && provider.recentOrders.isEmpty)
        Center(child: Padding(padding: const EdgeInsets.all(AppSizes.md), child: Column(children: [Text(provider.recentOrdersError!, textAlign: TextAlign.center), TextButton(onPressed: provider.fetchDashboardData, child: const Text('تلاش مجدد'))])))
      else if (provider.isLoading && provider.recentOrders.isEmpty)
        const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
      else if (provider.recentOrders.isEmpty)
        const SizedBox(height: 100, child: Center(child: Text('سفارشی برای نمایش وجود ندارد.')))
      else
        SizedBox(height: 300, child: ListView.separated(
          itemCount: provider.recentOrders.length,
          separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.getBorder(context).withValues(alpha: .5)),
          itemBuilder: (context, index) {
            final order = provider.recentOrders[index];
            final customer = order.customerName.trim().isEmpty ? 'مشتری ${order.userId.substring(0, order.userId.length < 6 ? order.userId.length : 6)}' : order.customerName.trim();
            return InkWell(
              onTap: () => context.push('/orders/details/${order.id}'),
              child: Padding(padding: const EdgeInsets.symmetric(vertical: AppSizes.sm), child: Row(children: [
                CircleAvatar(backgroundColor: AppColors.getBackground(context), child: Text(customer.isEmpty ? '?' : customer.characters.first, style: const TextStyle(color: AppColors.primary))),
                const SizedBox(width: AppSizes.md),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(customer, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: AppColors.getPrimaryText(context))),
                  Text('سفارش ${order.id.substring(0, order.id.length < 8 ? order.id.length : 8)} • ${order.createdAt.toLocal()}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.getSecondaryText(context))),
                ])),
                const SizedBox(width: AppSizes.sm),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${_money(order.totalAmount)} تومان', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: AppColors.getPrimaryText(context))),
                  const SizedBox(height: 4),
                  CustomChip(label: _statusLabel(order.status), type: _statusType(order.status)),
                ]),
              ])),
            );
          },
        )),
    ])),
  );
}
