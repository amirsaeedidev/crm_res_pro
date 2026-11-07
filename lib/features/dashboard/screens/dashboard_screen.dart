import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/app_loading.dart';
import '../../../providers/dashboard_provider.dart';
import '../../../shared/widgets/empty_widget.dart';
import '../../../shared/widgets/error_widget.dart' as app_error;
import '../widgets/restaurant_sales_chart.dart';
import '../../../models/statistics_model.dart';
import '../widgets/recent_orders_list.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _period = 'month';
  String _source = 'all';
  String _paymentMode = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadDashboard();
    });
  }

  (DateTime?, DateTime?) _selectedRange() {
    final now = DateTime.now();
    switch (_period) {
      case 'today':
        return (DateTime(now.year, now.month, now.day), now);
      case 'week':
        return (now.subtract(const Duration(days: 7)), now);
      case '30d':
        return (now.subtract(const Duration(days: 30)), now);
      case 'all':
        return (null, null);
      case 'month':
      default:
        return (DateTime(now.year, now.month, 1), now);
    }
  }

  void _loadDashboard() {
    final (startAt, endAt) = _selectedRange();
    context.read<DashboardProvider>().fetchDashboardData(
          startAt: startAt,
          endAt: endAt,
          orderSource: _source,
          paymentMode: _paymentMode,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, _) {
        final stats = provider.statistics;

        if (provider.isLoading && stats == null) {
          return const Center(child: AppLoading());
        }
        if (provider.error != null && stats == null) {
          return app_error.AppErrorWidget(
            message: provider.error!,
            onRetry: _loadDashboard,
          );
        }

        return RefreshIndicator(
          onRefresh: () async => _loadDashboard(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1050;
              final medium = constraints.maxWidth >= 650;
              final metricWidth = wide
                  ? (constraints.maxWidth - 32) / 3
                  : medium
                      ? (constraints.maxWidth - 16) / 2
                      : constraints.maxWidth;

              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'داشبورد مدیریت',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'آمار زنده و تجمیع‌شده از اطلاعات واقعی Supabase',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    _buildFilters(context),
                    const SizedBox(height: 20),
                    if (stats == null)
                      const EmptyWidget(
                        title: 'آماری برای نمایش وجود ندارد',
                        message: 'پس از ثبت سفارش و فعالیت مشتریان، آمار در این بخش نمایش داده می‌شود.',
                        icon: Icons.analytics_outlined,
                      )
                    else ...[
                      _featuredSalesCard(context, stats),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _metricCard(context, 'کل سفارش‌ها', stats.totalOrders, Icons.receipt_long_outlined, metricWidth),
                          _metricCard(context, 'سفارش‌های امروز', stats.todayOrders, Icons.today_outlined, metricWidth),
                          _metricCard(context, 'در حال انجام', stats.inProgressOrders, Icons.pending_actions_outlined, metricWidth),
                          _metricCard(context, 'تکمیل‌شده', stats.completedOrders, Icons.task_alt_outlined, metricWidth),
                          _metricCard(context, 'لغوشده', stats.cancelledOrders, Icons.cancel_outlined, metricWidth),
                          _metricCard(context, 'کل مشتریان', stats.totalCustomers, Icons.groups_outlined, metricWidth),
                          _metricCard(context, 'مشتریان جدید', stats.newCustomers, Icons.person_add_alt_1_outlined, metricWidth),
                          _metricCard(context, 'مشتریان فعال', stats.activeCustomers, Icons.person_pin_circle_outlined, metricWidth),
                          _metricCard(context, 'میانگین سفارش', _money(stats.averageOrderAmount), Icons.calculate_outlined, metricWidth),
                          _metricCard(context, 'موجودی کیف پول', '${_money(stats.walletBalanceTotal)} تومان', Icons.account_balance_wallet_outlined, metricWidth),
                          _metricCard(context, 'امتیاز وفاداری', stats.loyaltyPointsTotal, Icons.stars_outlined, metricWidth),
                          _metricCard(context, 'استفاده از تخفیف', stats.discountUsageCount, Icons.discount_outlined, metricWidth),
                          _metricCard(context, 'مجموع تخفیف مصرف‌شده', '${_money(stats.totalDiscountAmount)} تومان', Icons.sell_outlined, metricWidth),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _breakdownCard(context, 'محصولات پرفروش', stats.topProducts, metricWidth, (item) => '${item.quantity} عدد · ${_money(item.amount)} تومان'),
                          _breakdownCard(context, 'دسته‌بندی‌های پرفروش', stats.topCategories, metricWidth, (item) => '${item.quantity} عدد · ${_money(item.amount)} تومان'),
                          _breakdownCard(context, 'کدهای تخفیف پرمصرف', stats.topDiscountCodes, metricWidth, (item) => '${item.count} بار · ${_money(item.amount)} تومان'),
                          _breakdownCard(context, 'تفکیک پرداخت', stats.paymentBreakdown, metricWidth, (item) => '${item.count} سفارش · ${_money(item.amount)} تومان'),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    const RestaurantSalesChart(),
                    const SizedBox(height: 24),
                    Text(
                      'آخرین سفارش‌ها',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    if (provider.recentOrdersError != null && provider.recentOrders.isEmpty && !provider.isLoading)
                      app_error.AppErrorWidget(
                        message: provider.recentOrdersError!,
                        onRetry: _loadDashboard,
                      )
                    else if (provider.recentOrders.isEmpty && provider.isLoading)
                      const SizedBox(height: 120, child: Center(child: AppLoading()))
                    else if (provider.recentOrders.isEmpty)
                      const EmptyWidget(
                        title: 'سفارشی وجود ندارد',
                        message: 'سفارش‌های ثبت‌شده در این بخش نمایش داده می‌شوند.',
                        icon: Icons.receipt_long_outlined,
                      )
                    else
                      const RecentOrdersList(),
                    if (provider.isLoading && stats != null)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator(),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildFilters(BuildContext context) {
    final decoration = const InputDecoration(
      border: OutlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<String>(
            value: _period,
            decoration: decoration.copyWith(labelText: 'بازه زمانی'),
            items: const [
              DropdownMenuItem(value: 'today', child: Text('امروز')),
              DropdownMenuItem(value: 'week', child: Text('۷ روز اخیر')),
              DropdownMenuItem(value: 'month', child: Text('ماه جاری')),
              DropdownMenuItem(value: '30d', child: Text('۳۰ روز اخیر')),
              DropdownMenuItem(value: 'all', child: Text('تمام دوره')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _period = value);
              _loadDashboard();
            },
          ),
        ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<String>(
            value: _source,
            decoration: decoration.copyWith(labelText: 'منبع سفارش'),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('همه منابع')),
              DropdownMenuItem(value: 'customer_app', child: Text('اپ مشتری')),
              DropdownMenuItem(value: 'crm_walk_in', child: Text('ثبت در CRM')),
              DropdownMenuItem(value: 'reservation', child: Text('رزرو')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _source = value);
              _loadDashboard();
            },
          ),
        ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<String>(
            value: _paymentMode,
            decoration: decoration.copyWith(labelText: 'نوع پرداخت'),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('Mock و واقعی')),
              DropdownMenuItem(value: 'mock', child: Text('فقط Mock')),
              DropdownMenuItem(value: 'real', child: Text('فقط واقعی')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _paymentMode = value);
              _loadDashboard();
            },
          ),
        ),
      ],
    );
  }

  Widget _featuredSalesCard(BuildContext context, StatisticsModel stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const Icon(Icons.account_balance_wallet_outlined, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('مجموع فروش سفارش‌های تکمیل‌شده', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    '${_money(stats.totalSales)} تومان',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricCard(
    BuildContext context,
    String title,
    Object value,
    IconData icon,
    double width,
  ) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Text(
                      value.toString(),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _breakdownCard(
    BuildContext context,
    String title,
    List<DashboardBreakdownItem> items,
    double width,
    String Function(DashboardBreakdownItem) subtitle,
  ) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              if (items.isEmpty)
                const Text('داده‌ای برای این بازه وجود ندارد.')
              else
                ...items.take(5).map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Expanded(child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                            const SizedBox(width: 8),
                            Text(subtitle(item), style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  String _money(num value) => value.toStringAsFixed(0);
}
