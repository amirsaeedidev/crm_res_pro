import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_loading.dart';
import '../../../providers/reports_provider.dart';
import '../../../shared/widgets/empty_widget.dart';
import '../../../shared/widgets/error_widget.dart' as app_error;

enum DateRangeFilter { today, thisWeek, thisMonth, custom }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateRangeFilter _selectedFilter = DateRangeFilter.thisMonth;
  DateTimeRange? _customDateRange;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fetchReport();
    });
  }

  (DateTime, DateTime) _getDateRange() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    switch (_selectedFilter) {
      case DateRangeFilter.today:
        return (todayStart, now);
      case DateRangeFilter.thisWeek:
        return (todayStart.subtract(Duration(days: now.weekday - 1)), now);
      case DateRangeFilter.thisMonth:
        return (DateTime(now.year, now.month, 1), now);
      case DateRangeFilter.custom:
        if (_customDateRange == null) return (DateTime(now.year, now.month, 1), now);
        final inclusiveEndDay = _customDateRange!.end;
        final endExclusive = DateTime(
          inclusiveEndDay.year,
          inclusiveEndDay.month,
          inclusiveEndDay.day + 1,
        ).subtract(const Duration(microseconds: 1));
        return (_customDateRange!.start, endExclusive);
    }
  }

  void _fetchReport() {
    final provider = context.read<ReportsProvider>();
    final (startDate, endDate) = _getDateRange();
    provider.fetchSalesReport(startDate: startDate, endDate: endDate);
    provider.fetchTopProductsReport();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _customDateRange,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: AppColors.primary,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _customDateRange = picked;
      _selectedFilter = DateRangeFilter.custom;
    });
    _fetchReport();
  }

  num _num(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _number(num value) => value.round().toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );

  String _percentage(num value) => '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}٪';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSizes.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('گزارش‌ها و آمار', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: AppColors.getPrimaryText(context))),
          const SizedBox(height: AppSizes.lg),
          _buildDateFilters(),
          const SizedBox(height: AppSizes.lg),
          Consumer<ReportsProvider>(
            builder: (context, provider, child) {
              if (provider.isLoading && provider.salesReport == null) return const Center(child: AppLoading(size: 40));
              if (provider.error != null && provider.salesReport == null) {
                return app_error.AppErrorWidget(message: provider.error!, onRetry: _fetchReport);
              }
              final report = provider.salesReport;
              if (report == null) {
                return const EmptyWidget(title: 'داده‌ای موجود نیست', message: 'گزارش واقعی برای این بازه در دسترس نیست.', icon: Icons.bar_chart_outlined);
              }
              final summary = report.summary;
              final sales = _num(summary, 'total_sales');
              final orderCount = _num(summary, 'total_orders');
              final growth = _num(summary, 'growth_percentage');
              final typeCounts = <({String label, num count, Color color})>[
                (label: 'ارسال', count: _num(summary, 'delivery_count'), color: AppColors.primary),
                (label: 'دریافت حضوری', count: _num(summary, 'pickup_count'), color: AppColors.secondary),
                (label: 'سالن', count: _num(summary, 'dine_in_count'), color: AppColors.success),
              ];
              final typeTotal = typeCounts.fold<num>(0, (total, item) => total + item.count);
              final topProducts = provider.topProductsReport?.chartData ?? const <Map<String, dynamic>>[];

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(builder: (context, constraints) {
                    final mobile = constraints.maxWidth < 600;
                    final cards = [
                      _buildSummaryCard(context, 'فروش سفارش‌های تکمیل‌شده', '${_number(sales)} تومان', AppColors.primary, Icons.payments_outlined),
                      _buildSummaryCard(context, 'تعداد سفارش‌های تکمیل‌شده', _number(orderCount), AppColors.secondary, Icons.receipt_long_outlined),
                      _buildSummaryCard(context, 'رشد نسبت به بازه قبل', _percentage(growth), growth >= 0 ? AppColors.success : AppColors.error, Icons.trending_up),
                    ];
                    return Flex(
                      direction: mobile ? Axis.vertical : Axis.horizontal,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: cards.expand((card) => mobile ? [card, const SizedBox(height: AppSizes.md)] : [Expanded(child: card), const SizedBox(width: AppSizes.md)]).toList()..removeLast(),
                    );
                  }),
                  const SizedBox(height: AppSizes.lg),
                  AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('ترکیب سفارش‌های تکمیل‌شده', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: AppSizes.md),
                    if (typeTotal == 0)
                      const SizedBox(height: 160, child: Center(child: Text('در این بازه سفارش تکمیل‌شده‌ای وجود ندارد.')))
                    else
                      SizedBox(height: 240, child: PieChart(PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 42,
                        sections: typeCounts.where((item) => item.count > 0).map((item) {
                          final percent = item.count / typeTotal * 100;
                          return PieChartSectionData(
                            color: item.color,
                            value: item.count.toDouble(),
                            title: '${percent.toStringAsFixed(0)}٪',
                            radius: 50,
                            titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          );
                        }).toList(),
                      ))),
                    const SizedBox(height: AppSizes.md),
                    Wrap(spacing: AppSizes.lg, runSpacing: AppSizes.sm, alignment: WrapAlignment.center, children: typeCounts.map((item) => _buildLegend(context, item.color, '${item.label}: ${_number(item.count)}')).toList()),
                  ])),
                  const SizedBox(height: AppSizes.lg),
                  AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('۱۰ محصول پرفروش', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const Divider(height: AppSizes.lg),
                    if (provider.isLoading && provider.topProductsReport == null)
                      const Center(child: CircularProgressIndicator())
                    else if (topProducts.isEmpty)
                      const Text('داده‌ای برای محصولات پرفروش وجود ندارد.')
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: topProducts.length,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (context, index) => _buildTopProductRow(context, topProducts[index]),
                      ),
                  ])),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDateFilters() => Wrap(spacing: AppSizes.sm, runSpacing: AppSizes.sm, children: [
        _buildFilterChip('امروز', DateRangeFilter.today),
        _buildFilterChip('این هفته', DateRangeFilter.thisWeek),
        _buildFilterChip('این ماه', DateRangeFilter.thisMonth),
        ActionChip(
          label: Text(_customDateRange != null ? 'دلخواه: ${_customDateRange!.start.day}/${_customDateRange!.start.month} - ${_customDateRange!.end.day}/${_customDateRange!.end.month}' : 'بازه دلخواه', style: TextStyle(color: _selectedFilter == DateRangeFilter.custom ? Colors.white : AppColors.getPrimaryText(context))),
          backgroundColor: _selectedFilter == DateRangeFilter.custom ? AppColors.primary : AppColors.getSurface(context),
          onPressed: _pickCustomRange,
        ),
      ]);

  Widget _buildFilterChip(String label, DateRangeFilter filter) {
    final selected = _selectedFilter == filter;
    return ChoiceChip(
      label: Text(label, style: TextStyle(color: selected ? Colors.white : AppColors.getPrimaryText(context))),
      selected: selected,
      selectedColor: AppColors.primary,
      onSelected: (value) {
        if (!value) return;
        setState(() => _selectedFilter = filter);
        _fetchReport();
      },
    );
  }

  Widget _buildSummaryCard(BuildContext context, String title, String value, Color color, IconData icon) => AppCard(
        child: Row(children: [
          Container(padding: const EdgeInsets.all(AppSizes.md), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadius.medium)), child: Icon(icon, color: color)),
          const SizedBox(width: AppSizes.md),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.getSecondaryText(context)), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          ])),
        ]),
      );

  Widget _buildLegend(BuildContext context, Color color, String label) => Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))), const SizedBox(width: AppSizes.xs), Text(label, style: Theme.of(context).textTheme.bodyMedium)]);

  Widget _buildTopProductRow(BuildContext context, Map<String, dynamic> product) {
    final name = (product['product_name'] ?? '').toString().trim();
    final quantity = product['quantity'] is num ? (product['quantity'] as num).toInt() : int.tryParse('${product['quantity']}') ?? 0;
    final revenue = product['total_amount'] is num ? (product['total_amount'] as num).toDouble() : double.tryParse('${product['total_amount']}') ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.getBackground(context), borderRadius: BorderRadius.circular(AppRadius.small)), child: Icon(Icons.fastfood, color: AppColors.getSecondaryText(context))),
        const SizedBox(width: AppSizes.md),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name.isEmpty ? 'محصول بدون نام' : name, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
          Text('${_number(quantity)} عدد فروخته شد', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.getSecondaryText(context))),
        ])),
        Text('${_number(revenue)} تومان', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
      ]),
    );
  }
}
