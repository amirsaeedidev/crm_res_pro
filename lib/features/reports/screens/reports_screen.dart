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

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  DateRangeFilter _selectedFilter = DateRangeFilter.thisMonth;
  DateTimeRange? _customDateRange;

  static const _ink = Color(0xFF14264B);
  static const _blue = Color(0xFF3977EE);
  static const _paleBlue = Color(0xFFEAF1FF);
  static const _page = Color(0xFFF5F8FF);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fetchReport();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
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
        final end = _customDateRange!.end;
        return (
          _customDateRange!.start,
          DateTime(end.year, end.month, end.day + 1).subtract(const Duration(microseconds: 1)),
        );
    }
  }

  void _fetchReport() {
    final provider = context.read<ReportsProvider>();
    final (startDate, endDate) = _getDateRange();
    provider.fetchSalesReport(startDate: startDate, endDate: endDate);
    provider.fetchTopProductsReport();
    provider.fetchCustomerDistributionReport();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _customDateRange,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: _blue,
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

  String _digits(Object? value) {
    const latin = '0123456789';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    var result = value?.toString() ?? '';
    for (var i = 0; i < latin.length; i++) {
      result = result.replaceAll(latin[i], persian[i]);
    }
    return result;
  }

  String _number(num value) => _digits(value.round().toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => '٬',
      ));

  String _percentage(num value) =>
      '${value >= 0 ? '+' : ''}${_digits(value.toStringAsFixed(1))}٪';

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _page,
      child: Consumer<ReportsProvider>(
        builder: (context, provider, _) {
          final report = provider.salesReport;
          if (provider.isLoading && report == null) {
            return const Center(child: AppLoading(size: 40));
          }
          if (provider.error != null && report == null) {
            return app_error.AppErrorWidget(message: provider.error!, onRetry: _fetchReport);
          }
          if (report == null) {
            return const EmptyWidget(
              title: 'داده‌ای موجود نیست',
              message: 'گزارش واقعی برای این بازه در دسترس نیست.',
              icon: Icons.bar_chart_outlined,
            );
          }

          final summary = report.summary;
          final sales = _num(summary, 'total_sales');
          final orders = _num(summary, 'total_orders');
          final growth = _num(summary, 'growth_percentage');
          final types = <({String label, num count, Color color, IconData icon})>[
            (label: 'ارسال', count: _num(summary, 'delivery_count'), color: _blue, icon: Icons.delivery_dining_outlined),
            (label: 'دریافت حضوری', count: _num(summary, 'pickup_count'), color: const Color(0xFF65C99A), icon: Icons.shopping_bag_outlined),
            (label: 'سالن', count: _num(summary, 'dine_in_count'), color: const Color(0xFF8B72E8), icon: Icons.restaurant_outlined),
          ];
          final totalTypes = types.fold<num>(0, (sum, item) => sum + item.count);
          final products = provider.topProductsReport?.chartData ?? const <Map<String, dynamic>>[];
          final customers = provider.customerDistributionReport;

          return LayoutBuilder(builder: (context, constraints) {
            final mobile = constraints.maxWidth < 640;
            final horizontal = mobile ? 16.0 : 28.0;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(horizontal, 22, horizontal, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context, mobile),
                  const SizedBox(height: 22),
                  _buildDateFilters(),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE5EBF7)),
                    ),
                    child: TabBar(
                      controller: _tabs,
                      isScrollable: mobile,
                      tabAlignment: mobile ? TabAlignment.start : TabAlignment.fill,
                      dividerColor: Colors.transparent,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color: _ink,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: const Color(0xFF6C7892),
                      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      tabs: const [
                        Tab(icon: Icon(Icons.dashboard_outlined, size: 18), text: 'نمای کلی'),
                        Tab(icon: Icon(Icons.trending_up, size: 18), text: 'فروش'),
                        Tab(icon: Icon(Icons.fastfood_outlined, size: 18), text: 'محصولات'),
                        Tab(icon: Icon(Icons.people_alt_outlined, size: 18), text: 'مشتریان'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  AnimatedBuilder(
                    animation: _tabs,
                    builder: (context, _) => IndexedStack(
                      index: _tabs.index,
                      children: [
                        _overviewTab(context, mobile, summary, sales, orders, growth, types, totalTypes, products),
                        _salesTab(context, mobile, summary, sales, orders, growth, types, totalTypes),
                        _productsTab(context, products, provider.isLoading),
                        _customersTab(context, customers?.summary ?? const {}, customers?.chartData ?? const [], provider.isLoading),
                      ],
                    ),
                  ),
                ],
              ),
            );
          });
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool mobile) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_blue, Color(0xFF6A9AFF)]),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: _blue.withValues(alpha: .18), blurRadius: 16, offset: const Offset(0, 7))],
          ),
          child: const Icon(Icons.insights_rounded, color: Colors.white, size: 25),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('گزارشات رستوران', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: _ink, fontWeight: FontWeight.w800, fontSize: mobile ? 22 : 27)),
              const SizedBox(height: 5),
              Text('تصویر دقیق‌تری از فروش و عملکرد رستوران داشته باشید.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF75819A))),
            ],
          ),
        ),
        if (!mobile)
          IconButton(
            tooltip: 'بروزرسانی گزارش‌ها',
            onPressed: _fetchReport,
            style: IconButton.styleFrom(backgroundColor: Colors.white, foregroundColor: _ink),
            icon: const Icon(Icons.refresh_rounded),
          ),
      ],
    );
  }

  Widget _buildDateFilters() => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _filterChip('امروز', DateRangeFilter.today),
          _filterChip('این هفته', DateRangeFilter.thisWeek),
          _filterChip('این ماه', DateRangeFilter.thisMonth),
          ActionChip(
            avatar: const Icon(Icons.date_range_rounded, size: 17),
            label: Text(_customDateRange == null
                ? 'بازه دلخواه'
                : '${_digits(_customDateRange!.start.day)}/${_digits(_customDateRange!.start.month)} تا ${_digits(_customDateRange!.end.day)}/${_digits(_customDateRange!.end.month)}'),
            backgroundColor: _selectedFilter == DateRangeFilter.custom ? _paleBlue : Colors.white,
            side: BorderSide(color: _selectedFilter == DateRangeFilter.custom ? _blue : const Color(0xFFE3E9F4)),
            onPressed: _pickCustomRange,
          ),
        ],
      );

  Widget _filterChip(String label, DateRangeFilter filter) {
    final selected = _selectedFilter == filter;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      backgroundColor: Colors.white,
      selectedColor: _ink,
      labelStyle: TextStyle(color: selected ? Colors.white : const Color(0xFF6C7892), fontWeight: FontWeight.w600),
      side: BorderSide(color: selected ? _ink : const Color(0xFFE3E9F4)),
      onSelected: (value) {
        if (!value) return;
        setState(() => _selectedFilter = filter);
        _fetchReport();
      },
    );
  }

  Widget _overviewTab(
    BuildContext context, bool mobile, Map<String, dynamic> summary,
    num sales, num orders, num growth,
    List<({String label, num count, Color color, IconData icon})> types,
    num totalTypes, List<Map<String, dynamic>> products,
  ) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _metricGrid(context, mobile, [
        _metric('فروش تکمیل‌شده', '${_number(sales)} تومان', Icons.payments_outlined, _blue, 'مجموع فروش در بازه انتخابی'),
        _metric('سفارش‌های تکمیل‌شده', _number(orders), Icons.receipt_long_outlined, const Color(0xFF8B72E8), 'تعداد سفارش‌های نهایی‌شده'),
        _metric('رشد فروش', _percentage(growth), Icons.show_chart_rounded, growth >= 0 ? const Color(0xFF39B982) : const Color(0xFFE45B70), 'در مقایسه با بازه قبل'),
      ]),
      const SizedBox(height: 18),
      _sectionCard(
        title: 'ترکیب روش سفارش',
        subtitle: 'سهم هر روش از سفارش‌های تکمیل‌شده',
        icon: Icons.donut_large_rounded,
        child: totalTypes == 0
            ? const _NoData(message: 'در این بازه سفارش تکمیل‌شده‌ای ثبت نشده است.')
            : Column(children: [
                SizedBox(
                  height: 210,
                  child: PieChart(PieChartData(
                    sectionsSpace: 4,
                    centerSpaceRadius: 48,
                    sections: types.where((item) => item.count > 0).map((item) => PieChartSectionData(
                      color: item.color,
                      value: item.count.toDouble(),
                      title: '${(item.count / totalTypes * 100).toStringAsFixed(0)}٪',
                      radius: 43,
                      titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    )).toList(),
                  )),
                ),
                Wrap(spacing: 16, runSpacing: 12, alignment: WrapAlignment.center, children: types.map((item) => _legend(item.color, '${item.label} · ${_number(item.count)}')).toList()),
              ]),
      ),
      const SizedBox(height: 18),
      _sectionCard(
        title: 'محصولات پرفروش',
        subtitle: 'محصولات برتر بر اساس داده‌های ثبت‌شده',
        icon: Icons.local_fire_department_outlined,
        trailing: TextButton(onPressed: () => _tabs.animateTo(2), child: const Text('همه محصولات')),
        child: products.isEmpty
            ? const _NoData(message: 'اطلاعات محصولات پرفروش در دسترس نیست.')
            : Column(children: products.take(5).toList().asMap().entries.map((entry) => _productRow(context, entry.value, entry.key)).toList()),
      ),
    ]);
  }

  Widget _salesTab(
    BuildContext context, bool mobile, Map<String, dynamic> summary,
    num sales, num orders, num growth,
    List<({String label, num count, Color color, IconData icon})> types,
    num totalTypes,
  ) {
    final chart = context.read<ReportsProvider>().salesReport?.chartData ?? const <Map<String, dynamic>>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _metricGrid(context, mobile, [
        _metric('مجموع فروش', '${_number(sales)} تومان', Icons.account_balance_wallet_outlined, _blue, 'بر اساس سفارش‌های تکمیل‌شده'),
        _metric('میانگین هر سفارش', orders > 0 ? '${_number(sales / orders)} تومان' : '۰ تومان', Icons.calculate_outlined, const Color(0xFF8B72E8), 'فروش تقسیم بر تعداد سفارش'),
        _metric('تغییر نسبت به قبل', _percentage(growth), Icons.compare_arrows_rounded, growth >= 0 ? const Color(0xFF39B982) : const Color(0xFFE45B70), 'درصد تغییر فروش'),
      ]),
      const SizedBox(height: 18),
      _sectionCard(
        title: 'روند فروش',
        subtitle: 'مقادیر نمودار بر اساس داده‌ای است که گزارش فروش برمی‌گرداند',
        icon: Icons.bar_chart_rounded,
        child: chart.isEmpty
            ? const _NoData(message: 'داده نموداری برای این بازه موجود نیست.')
            : SizedBox(
                height: 250,
                child: BarChart(BarChartData(
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44, getTitlesWidget: (value, meta) => Text(_compact(value), style: const TextStyle(fontSize: 10, color: Color(0xFF8792A8))))),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= chart.length) return const SizedBox.shrink();
                      final item = chart[index];
                      final label = item['label'] ?? item['date'] ?? item['month'] ?? '';
                      return Padding(padding: const EdgeInsets.only(top: 8), child: Text('$label', style: const TextStyle(fontSize: 10, color: Color(0xFF8792A8))));
                    })),
                  ),
                  barGroups: chart.asMap().entries.map((entry) {
                    final item = entry.value;
                    final amount = _num(item, 'total_sales') != 0 ? _num(item, 'total_sales') : _num(item, 'sales');
                    return BarChartGroupData(x: entry.key, barRods: [BarChartRodData(toY: amount.toDouble(), width: mobile ? 13 : 22, borderRadius: BorderRadius.circular(7), color: _blue, backDrawRodData: BackgroundBarChartRodData(show: true, toY: chart.map((e) => (_num(e, 'total_sales') != 0 ? _num(e, 'total_sales') : _num(e, 'sales')).toDouble()).fold<double>(0, (a, b) => a > b ? a : b), color: const Color(0xFFF0F4FC)))]);
                  }).toList(),
                )),
              ),
      ),
      const SizedBox(height: 18),
      _sectionCard(title: 'تفکیک روش سفارش', subtitle: 'تعداد سفارش‌ها بر اساس نوع سرویس', icon: Icons.pie_chart_outline_rounded,
        child: totalTypes == 0 ? const _NoData(message: 'داده‌ای برای تفکیک روش سفارش وجود ندارد.') : Column(children: types.map((item) {
          final ratio = (item.count / totalTypes).clamp(0.0, 1.0).toDouble();
          return Padding(padding: const EdgeInsets.only(bottom: 16), child: Column(children: [
            Row(children: [Icon(item.icon, size: 18, color: item.color), const SizedBox(width: 8), Expanded(child: Text(item.label, style: const TextStyle(fontWeight: FontWeight.w600, color: _ink))), Text('${_number(item.count)} · ${(ratio * 100).toStringAsFixed(0)}٪', style: const TextStyle(color: Color(0xFF77839A)))]),
            const SizedBox(height: 9),
            ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: ratio, minHeight: 8, backgroundColor: const Color(0xFFF0F3FA), color: item.color)),
          ]));
        }).toList()),
      ),
    ]);
  }

  Widget _productsTab(BuildContext context, List<Map<String, dynamic>> products, bool loading) {
    return _sectionCard(
      title: 'عملکرد محصولات',
      subtitle: 'فهرست واقعی محصولات برگشتی از گزارش Supabase',
      icon: Icons.fastfood_outlined,
      child: loading && products.isEmpty
          ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          : products.isEmpty
              ? const _NoData(message: 'اطلاعاتی برای محصولات پرفروش پیدا نشد.')
              : Column(children: products.asMap().entries.map((entry) => _productRow(context, entry.value, entry.key)).toList()),
    );
  }

  Widget _customersTab(BuildContext context, Map<String, dynamic> summary, List<Map<String, dynamic>> chart, bool loading) {
    if (loading && summary.isEmpty && chart.isEmpty) {
      return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
    }
    if (summary.isEmpty && chart.isEmpty) {
      return _sectionCard(title: 'گزارش مشتریان', subtitle: 'توزیع مشتریان از داده‌های واقعی', icon: Icons.people_alt_outlined,
        child: const _NoData(message: 'گزارش مشتریان هنوز داده‌ای برنگردانده است.'));
    }
    final entries = summary.entries.toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (entries.isNotEmpty)
        _metricGrid(context, MediaQuery.sizeOf(context).width < 640, entries.take(4).map((entry) => _metric(
          _humanize(entry.key), _number(_asNum(entry.value)), Icons.people_outline_rounded, _blue, 'مقدار برگشتی از گزارش مشتریان',
        )).toList()),
      const SizedBox(height: 18),
      _sectionCard(title: 'توزیع مشتریان', subtitle: 'دسته‌بندی برگشتی از Supabase', icon: Icons.groups_2_outlined,
        child: chart.isEmpty ? const _NoData(message: 'جزئیات دسته‌بندی مشتریان موجود نیست.') : Column(
          children: chart.asMap().entries.map((entry) {
            final row = entry.value;
            final label = (row['label'] ?? row['customer_type'] ?? row['segment'] ?? row['name'] ?? 'دسته ${entry.key + 1}').toString();
            final amount = _asNum(row['count'] ?? row['total'] ?? row['value'] ?? row['customers']);
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(backgroundColor: _paleBlue, foregroundColor: _blue, child: Text(_digits(entry.key + 1))),
              title: Text(label, style: const TextStyle(color: _ink, fontWeight: FontWeight.w600)),
              trailing: Text(_number(amount), style: const TextStyle(color: _ink, fontWeight: FontWeight.bold)),
            );
          }).toList(),
        )),
    ]);
  }

  Widget _metricGrid(BuildContext context, bool mobile, List<Widget> cards) {
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1000 ? 3 : constraints.maxWidth >= 620 ? 2 : 1;
      final ratio = columns == 1 ? 3.4 : 1.65;
      return GridView.count(
        crossAxisCount: columns,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: ratio,
        children: cards,
      );
    });
  }

  Widget _metric(String title, String value, IconData icon, Color color, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE7ECF6)), boxShadow: const [BoxShadow(color: Color(0x070F2450), blurRadius: 18, offset: Offset(0, 6))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: color.withValues(alpha: .11), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 21)),
          const Spacer(),
          const Icon(Icons.north_east_rounded, size: 16, color: Color(0xFF9AA5BA)),
        ]),
        const SizedBox(height: 12),
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF7B879D), fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        FittedBox(alignment: Alignment.centerRight, fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 21))),
        const SizedBox(height: 4),
        Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF9AA4B7), fontSize: 10)),
      ]),
    );
  }

  Widget _sectionCard({required String title, required String subtitle, required IconData icon, required Widget child, Widget? trailing}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFE7ECF6)), boxShadow: const [BoxShadow(color: Color(0x060F2450), blurRadius: 18, offset: Offset(0, 6))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: _paleBlue, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: _blue, size: 20)),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(color: Color(0xFF8792A8), fontSize: 11)),
          ])),
          if (trailing != null) trailing,
        ]),
        const SizedBox(height: 20),
        child,
      ]),
    );
  }

  Widget _productRow(BuildContext context, Map<String, dynamic> product, int index) {
    final name = (product['product_name'] ?? product['name'] ?? '').toString().trim();
    final quantity = _asNum(product['quantity'] ?? product['total_quantity']);
    final revenue = _asNum(product['total_amount'] ?? product['revenue'] ?? product['total_sales']);
    final rankColors = [const Color(0xFF3977EE), const Color(0xFF8B72E8), const Color(0xFF65C99A)];
    final color = rankColors[index % rankColors.length];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(children: [
        Container(width: 38, height: 38, alignment: Alignment.center, decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(12)), child: Text(_digits(index + 1), style: TextStyle(color: color, fontWeight: FontWeight.w800))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name.isEmpty ? 'محصول بدون نام' : name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('${_number(quantity)} عدد فروش', style: const TextStyle(color: Color(0xFF8792A8), fontSize: 11)),
        ])),
        const SizedBox(width: 8),
        Flexible(child: Text('${_number(revenue)} تومان', textAlign: TextAlign.end, style: const TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 12))),
      ]),
    );
  }

  Widget _legend(Color color, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
    const SizedBox(width: 7),
    Text(label, style: const TextStyle(color: Color(0xFF68758E), fontSize: 12)),
  ]);

  num _asNum(Object? value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _compact(double value) {
    if (value.abs() >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}م';
    if (value.abs() >= 1000) return '${(value / 1000).toStringAsFixed(0)}ه';
    return _digits(value.round());
  }

  String _humanize(String key) {
    const labels = {
      'total_customers': 'کل مشتریان',
      'new_customers': 'مشتریان جدید',
      'returning_customers': 'مشتریان بازگشتی',
      'active_customers': 'مشتریان فعال',
      'customer_count': 'تعداد مشتریان',
      'total': 'مجموع',
    };
    if (labels.containsKey(key)) return labels[key]!;
    return key.replaceAll('_', ' ');
  }
}

class _NoData extends StatelessWidget {
  const _NoData({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xFFF0F4FC), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.insert_chart_outlined_rounded, color: Color(0xFF8290AA))),
      const SizedBox(height: 10),
      Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF8792A8), fontSize: 13)),
    ])),
  );
}
