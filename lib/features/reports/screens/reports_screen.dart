import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/services/supabase_service.dart';
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
    _tabs = TabController(length: 10, vsync: this);
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
    provider.fetchFinancialReport(startDate: startDate, endDate: endDate);
    provider.fetchInventoryReport(startDate: startDate, endDate: endDate);
    provider.fetchOrderHealthReport(startDate: startDate, endDate: endDate);
    provider.fetchTableUsageReport(startDate: startDate, endDate: endDate);
    provider.fetchDishProfitReport(startDate: startDate, endDate: endDate);
    provider.fetchPaymentReconciliationReport(startDate: startDate, endDate: endDate);
  }

  String _jalaliDate(DateTime date) {
    final j = Jalali.fromDateTime(date);
    return '${j.year.toString().padLeft(4, '0')}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}';
  }

  int? _parseDatePart(String value) {
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    const ar = '٠١٢٣٤٥٦٧٨٩';
    var normalized = value.trim();
    for (var i = 0; i < 10; i++) {
      normalized = normalized.replaceAll(fa[i], '$i').replaceAll(ar[i], '$i');
    }
    return int.tryParse(normalized);
  }

  DateTime? _parseJalaliDate(String value) {
    final parts = value.trim().split(RegExp(r'[/.-]'));
    if (parts.length != 3) return null;
    final y = _parseDatePart(parts[0]);
    final m = _parseDatePart(parts[1]);
    final d = _parseDatePart(parts[2]);
    if (y == null || m == null || d == null || y < 1300 || y > 1500 || m < 1 || m > 12 || d < 1 || d > 31) return null;
    try {
      final date = Jalali(y, m, d).toDateTime();
      if (_jalaliDate(date) != '${y.toString().padLeft(4, '0')}/${m.toString().padLeft(2, '0')}/${d.toString().padLeft(2, '0')}') return null;
      return DateTime(date.year, date.month, date.day);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final defaultStart = _customDateRange?.start ?? DateTime(now.year, now.month, 1);
    final defaultEnd = _customDateRange?.end ?? DateTime(now.year, now.month, now.day);
    final start = TextEditingController(text: _jalaliDate(defaultStart));
    final end = TextEditingController(text: _jalaliDate(defaultEnd));
    final form = GlobalKey<FormState>();
    final picked = await showDialog<DateTimeRange>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('انتخاب بازه شمسی'),
        content: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: start, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'از تاریخ (۱۴۰۵/۰۱/۰۱)'), validator: (v) => _parseJalaliDate(v ?? '') == null ? 'تاریخ شمسی معتبر وارد کنید' : null),
            const SizedBox(height: 12),
            TextFormField(controller: end, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'تا تاریخ (۱۴۰۵/۰۱/۳۱)'), validator: (v) => _parseJalaliDate(v ?? '') == null ? 'تاریخ شمسی معتبر وارد کنید' : null),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
          FilledButton(onPressed: () {
            if (!form.currentState!.validate()) return;
            final from = _parseJalaliDate(start.text)!;
            final to = _parseJalaliDate(end.text)!;
            if (to.isBefore(from)) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('تاریخ پایان نباید قبل از تاریخ شروع باشد.')));
              return;
            }
            Navigator.pop(dialogContext, DateTimeRange(start: from, end: to));
          }, child: const Text('اعمال بازه')),
        ],
      ),
    );
    start.dispose();
    end.dispose();
    if (!mounted || picked == null) return;
    setState(() {
      _customDateRange = picked;
      _selectedFilter = DateRangeFilter.custom;
    });
    _fetchReport();
  }

  List<List<String>> _buildExportRows() {
    final provider = context.read<ReportsProvider>();
    final (from, to) = _getDateRange();
    final rows = <List<String>>[
      ['گزارش جامع رستوران'],
      ['بازه شمسی', '${_jalaliDate(from)} تا ${_jalaliDate(to)}'],
      ['واحد پول', 'تومان'],
      [],
    ];
    void addSummary(String title, Map<String, dynamic>? summary) {
      if (summary == null || summary.isEmpty) return;
      rows.add([title]);
      summary.forEach((key, value) => rows.add([key, value?.toString() ?? '']));
      rows.add([]);
    }
    void addTable(String title, List<Map<String, dynamic>> data) {
      if (data.isEmpty) return;
      final keys = <String>[];
      for (final item in data) {
        for (final key in item.keys) {
          if (!keys.contains(key)) keys.add(key);
        }
      }
      rows.add([title]);
      rows.add(keys);
      for (final item in data) {
        rows.add(keys.map((key) => item[key]?.toString() ?? '').toList());
      }
      rows.add([]);
    }
    addSummary('خلاصه فروش', provider.salesReport?.summary);
    addTable('روند فروش', provider.salesReport?.chartData ?? []);
    addSummary('گزارش مالی', provider.financialReport?.summary);
    addTable('ترکیب مالی', provider.financialReport?.chartData ?? []);
    addSummary('گزارش انبار', provider.inventoryReport?.summary);
    addTable('وضعیت مواد اولیه', provider.inventoryReport?.chartData ?? []);
    addSummary('سود هر غذا', provider.dishProfitReport?.summary);
    final dishRows = provider.dishProfitReport?.chartData ?? const <Map<String, dynamic>>[];
    final dishData = dishRows.isNotEmpty ? dishRows.first : const <String, dynamic>{};
    addTable('سودآوری غذاها', (dishData['dishes'] as List<dynamic>? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    addTable('سود روزانه', (dishData['daily'] as List<dynamic>? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    addTable('سود ماهانه', (dishData['monthly'] as List<dynamic>? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    addSummary('تطبیق پرداخت و صندوق', provider.paymentReconciliationReport?.summary);
    final paymentRows = provider.paymentReconciliationReport?.chartData ?? const <Map<String, dynamic>>[];
    final paymentData = paymentRows.isNotEmpty ? paymentRows.first : const <String, dynamic>{};
    addTable('روش‌های پرداخت', (paymentData['methods'] as List<dynamic>? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    addTable('بستن صندوق و مغایرت', (paymentData['closings'] as List<dynamic>? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    addTable('وضعیت سفارش‌ها', provider.orderHealthReport?.chartData ?? []);
    addTable('استفاده از میزها', provider.tableUsageReport?.chartData ?? []);
    return rows;
  }

  Future<void> _exportExcel() async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['گزارش رستوران'];
      for (final row in _buildExportRows()) {
        sheet.appendRow(row.map((cell) => TextCellValue(cell)).toList());
      }
      final bytes = excel.save();
      if (bytes == null) throw Exception('ساخت فایل Excel ناموفق بود');
      final (from, to) = _getDateRange();
      final path = await FilePicker.platform.saveFile(
        fileName: 'restaurant-report-${_jalaliDate(from)}-${_jalaliDate(to)}.xlsx',
        bytes: Uint8List.fromList(bytes),
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (path != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فایل Excel آماده و ذخیره شد.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خروجی Excel ناموفق بود: $e')));
    }
  }

  Future<void> _exportPdf() async {
    try {
      final font = pw.Font.ttf(await rootBundle.load('assets/fonts/Lalezar.ttf'));
      final pdf = pw.Document();
      final rows = _buildExportRows().where((row) => row.isNotEmpty).toList();
      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        theme: pw.ThemeData.withFont(base: font, bold: font),
        margin: const pw.EdgeInsets.all(24),
        build: (_) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text('گزارش جامع رستوران', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: font, fontSize: 20)),
                pw.SizedBox(height: 8),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey400, width: .4),
                  children: rows.map((row) => pw.TableRow(children: row.map((cell) => pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(cell, textAlign: pw.TextAlign.right, style: pw.TextStyle(font: font, fontSize: 8)),
                  )).toList())).toList(),
                ),
              ],
            ),
          ),
        ],
      ));
      final (from, to) = _getDateRange();
      final path = await FilePicker.platform.saveFile(
        fileName: 'restaurant-report-${_jalaliDate(from)}-${_jalaliDate(to)}.pdf',
        bytes: await pdf.save(),
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (path != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فایل PDF آماده و ذخیره شد.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خروجی PDF ناموفق بود: $e')));
    }
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
                        Tab(icon: Icon(Icons.account_balance_wallet_outlined, size: 18), text: 'مالی و سود'),
                        Tab(icon: Icon(Icons.inventory_2_outlined, size: 18), text: 'انبار'),
                        Tab(icon: Icon(Icons.warning_amber_rounded, size: 18), text: 'وضعیت سفارش‌ها'),
                        Tab(icon: Icon(Icons.table_restaurant_outlined, size: 18), text: 'میزها و ساعات شلوغی'),
                        Tab(icon: Icon(Icons.restaurant_menu_outlined, size: 18), text: 'سود هر غذا'),
                        Tab(icon: Icon(Icons.point_of_sale_outlined, size: 18), text: 'پرداخت و صندوق'),
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
                        _financialTab(context, mobile, provider.financialReport?.summary ?? const {}, provider.financialReport?.chartData ?? const [], provider.isLoading),
                        _inventoryTab(context, mobile, provider.inventoryReport?.summary ?? const {}, provider.inventoryReport?.chartData ?? const [], provider.isLoading),
                        _orderHealthTab(context, mobile, provider.orderHealthReport?.summary ?? const {}, provider.orderHealthReport?.chartData ?? const [], provider.isLoading),
                        _tableUsageTab(context, mobile, provider.tableUsageReport?.summary ?? const {}, provider.tableUsageReport?.chartData.isNotEmpty == true ? provider.tableUsageReport!.chartData.first : const {}, provider.isLoading),
                        _dishProfitTab(context, mobile, provider.dishProfitReport?.summary ?? const {}, provider.dishProfitReport?.chartData.isNotEmpty == true ? provider.dishProfitReport!.chartData.first : const {}, provider.isLoading),
                        _paymentReconciliationTab(context, mobile, provider.paymentReconciliationReport?.summary ?? const {}, provider.paymentReconciliationReport?.chartData.isNotEmpty == true ? provider.paymentReconciliationReport!.chartData.first : const {}, provider.isLoading),
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


  Widget _orderHealthTab(
    BuildContext context, bool mobile, Map<String, dynamic> summary,
    List<Map<String, dynamic>> rows, bool loading,
  ) {
    final cancelled = _num(summary, 'cancelled_count');
    final cancelledAmount = _num(summary, 'cancelled_amount');
    final delayed = _num(summary, 'delayed_count');
    final repeatCustomers = _num(summary, 'repeat_customer_count');
    Widget metric(String title, String value, IconData icon, Color color) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5EBF7))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color), const SizedBox(height: 10),
          Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(fontSize: 12, color: Color(0xFF75819A))),
        ]),
      ),
    );
    final cancelledRows = rows.where((r) => r['category'] == 'cancelled').toList();
    final delayedRows = rows.where((r) => r['category'] == 'delayed').toList();
    final repeatRows = rows.where((r) => r['category'] == 'repeat_customer').toList();
    Widget reportCard(String title, String subtitle, IconData icon, List<Map<String, dynamic>> items, String category) =>
      _sectionCard(title: title, subtitle: subtitle, icon: icon, child: items.isEmpty
        ? const _NoData(message: 'در بازه انتخاب‌شده موردی ثبت نشده است.')
        : Column(children: items.take(50).map((item) {
          final name = (item['customer_name'] ?? 'مشتری نامشخص').toString();
          final phone = (item['customer_phone'] ?? '').toString();
          final queue = item['daily_queue_number'];
          final orderLabel = queue == null ? '' : 'سفارش روز ${_digits(queue)} · ';
          final count = _num(item, 'order_count');
          final delay = _num(item, 'delay_minutes');
          final amount = _num(item, 'amount');
          final details = category == 'cancelled'
            ? '$orderLabelعلت: ${(item['reason'] ?? '').toString().isEmpty ? 'ثبت نشده' : item['reason']}'
            : category == 'delayed'
              ? '$orderLabelتأخیر: ${_digits(delay)} دقیقه · ${(item['status'] ?? '').toString()}'
              : '${_digits(count)} سفارش · ${_number(amount)} تومان مجموع خرید';
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: category == 'cancelled' ? const Color(0xFFFFE9ED) : category == 'delayed' ? const Color(0xFFFFF2DB) : _paleBlue,
              child: Icon(category == 'cancelled' ? Icons.cancel_outlined : category == 'delayed' ? Icons.timer_outlined : Icons.repeat_rounded,
                color: category == 'cancelled' ? const Color(0xFFE45B70) : category == 'delayed' ? const Color(0xFFB7791F) : _blue, size: 20),
            ),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${phone.isEmpty ? '' : '$phone · '}$details'),
            trailing: category == 'cancelled' ? Text('${_number(amount)} ت', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)) : null,
          );
        }).toList()));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (loading) const LinearProgressIndicator(minHeight: 2),
      Row(children: [
        metric('سفارش لغوشده', _number(cancelled), Icons.cancel_outlined, const Color(0xFFE45B70)),
        const SizedBox(width: 10),
        metric('سفارش تأخیردار', _number(delayed), Icons.timer_outlined, const Color(0xFFB7791F)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        metric('مشتری پرتکرار (۳+ سفارش)', _number(repeatCustomers), Icons.repeat_rounded, _blue),
        const SizedBox(width: 10),
        metric('مبلغ سفارش‌های لغوشده', '${_number(cancelledAmount)} تومان', Icons.payments_outlined, const Color(0xFF8B72E8)),
      ]),
      const SizedBox(height: 18),
      reportCard('سفارش‌های لغوشده', 'به همراه علت لغو و مبلغ سفارش', Icons.cancel_outlined, cancelledRows, 'cancelled'),
      const SizedBox(height: 16),
      reportCard('سفارش‌های تأخیردار', 'سفارش‌های فعال پس از زمان آماده‌سازی یا تکمیل‌شده دیرتر از زمان تخمینی', Icons.timer_outlined, delayedRows, 'delayed'),
      const SizedBox(height: 16),
      reportCard('مشتریان پرتکرار', 'مشتریانی با حداقل ۳ سفارش در بازه انتخابی', Icons.repeat_rounded, repeatRows, 'repeat_customer'),
    ]);
  }


  Widget _tableUsageTab(
    BuildContext context,
    bool mobile,
    Map<String, dynamic> summary,
    Map<String, dynamic> data,
    bool loading,
  ) {
    final tables = (data['tables'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final hours = (data['hours'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final peakHour = _num(summary, 'peak_hour').toInt();
    final peakLabel = '${peakHour.toString().padLeft(2, '0')}:00';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (loading) const LinearProgressIndicator(minHeight: 2),
      _metricGrid(context, mobile, [
        _metric('سفارش‌های سالن', _number(_num(summary, 'total_orders')), Icons.receipt_long_outlined, _blue, 'سفارش‌های غیرلغوشده در بازه'),
        _metric('مجموع زمان اشغال', '${_number(_num(summary, 'occupied_minutes') / 60)} ساعت', Icons.timer_outlined, const Color(0xFF8B72E8), 'زمان ثبت‌شده برای سفارش‌های سالن'),
        _metric('میانگین حضور', '${_number(_num(summary, 'average_minutes'))} دقیقه', Icons.hourglass_bottom_rounded, const Color(0xFF39B982), 'میانگین از شروع تا پایان سفارش'),
        _metric('شلوغ‌ترین ساعت', peakLabel, Icons.schedule_rounded, const Color(0xFFE9A23B), '${_number(_num(summary, 'peak_hour_orders'))} سفارش'),
      ]),
      const SizedBox(height: 18),
      _sectionCard(
        title: 'ساعات شلوغی رستوران',
        subtitle: 'تعداد سفارش‌های سالن بر اساس ساعت ثبت سفارش',
        icon: Icons.bar_chart_rounded,
        child: hours.isEmpty
          ? const _NoData(message: 'اطلاعاتی برای ساعات شلوغی وجود ندارد.')
          : SizedBox(
              height: 250,
              child: BarChart(BarChartData(
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(sideTitles: SideTitles(
                    showTitles: true, reservedSize: 32,
                    getTitlesWidget: (v, meta) => Text(_digits(v.toInt()), style: const TextStyle(fontSize: 10, color: Color(0xFF8792A8))),
                  )),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(
                    showTitles: true, interval: 3, reservedSize: 30,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i < 0 || i >= hours.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Text('${hours[i]['label']}', style: const TextStyle(fontSize: 9, color: Color(0xFF8792A8))),
                      );
                    },
                  )),
                ),
                barGroups: hours.asMap().entries.map((entry) {
                  final count = _num(entry.value, 'order_count').toDouble();
                  return BarChartGroupData(x: entry.key, barRods: [
                    BarChartRodData(
                      toY: count, width: mobile ? 6 : 10,
                      borderRadius: BorderRadius.circular(4),
                      color: entry.key == peakHour ? const Color(0xFFE9A23B) : _blue,
                    ),
                  ]);
                }).toList(),
              )),
            ),
      ),
      const SizedBox(height: 18),
      _sectionCard(
        title: 'عملکرد هر میز',
        subtitle: 'تعداد سفارش، مجموع زمان اشغال و میانگین زمان هر سفارش',
        icon: Icons.table_restaurant_outlined,
        child: tables.isEmpty
          ? const _NoData(message: 'میز فعالی برای گزارش وجود ندارد.')
          : Column(children: tables.map((item) {
              final count = _num(item, 'order_count');
              final minutes = _num(item, 'occupied_minutes');
              final average = _num(item, 'average_minutes');
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: _paleBlue,
                  foregroundColor: _blue,
                  child: Text(_digits(item['table_number'])),
                ),
                title: Text('میز ${_digits(item['table_number'])} · ظرفیت ${_digits(item['capacity'])} نفر',
                  style: const TextStyle(color: _ink, fontWeight: FontWeight.w700)),
                subtitle: Text('${_number(minutes / 60)} ساعت اشغال · میانگین ${_number(average)} دقیقه'),
                trailing: Text('${_number(count)} سفارش', style: const TextStyle(color: _ink, fontWeight: FontWeight.w700)),
              );
            }).toList()),
      ),
      const SizedBox(height: 10),
      const Text(
        'مبنای گزارش: سفارش‌های سالن متصل به میز. سفارش‌های لغوشده محاسبه نمی‌شوند؛ برای سفارش باز، زمان تا لحظه گزارش لحاظ می‌شود.',
        style: TextStyle(color: Color(0xFF8792A8), fontSize: 11),
      ),
    ]);
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
                ? 'بازه شمسی دلخواه'
                : '${_digits(_jalaliDate(_customDateRange!.start))} تا ${_digits(_jalaliDate(_customDateRange!.end))}'),
            backgroundColor: _selectedFilter == DateRangeFilter.custom ? _paleBlue : Colors.white,
            side: BorderSide(color: _selectedFilter == DateRangeFilter.custom ? _blue : const Color(0xFFE3E9F4)),
            onPressed: _pickCustomRange,
          ),
          ActionChip(avatar: const Icon(Icons.table_view_outlined, size: 17), label: const Text('خروجی Excel'), onPressed: _exportExcel),
          ActionChip(avatar: const Icon(Icons.picture_as_pdf_outlined, size: 17), label: const Text('خروجی PDF'), onPressed: _exportPdf),
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
    final grossSales = _num(summary, 'gross_sales');
    final discounts = _num(summary, 'discount_amount');
    final netSales = _num(summary, 'net_sales');
    final refunds = _num(summary, 'refund_amount');
    final netAfterRefunds = _num(summary, 'net_after_refunds');
    final deliveryFees = _num(summary, 'delivery_fees');
    final recordedRevenue = _num(summary, 'recorded_revenue');
    final cashReceived = _num(summary, 'cash_received_in_period');
    final receivable = _num(summary, 'receivable_balance');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _metricGrid(context, mobile, [
        _metric('فروش خالص', '${_number(netSales)} تومان', Icons.account_balance_wallet_outlined, _blue, 'فروش ناخالص پس از کسر تخفیف'),
        _metric('میانگین هر سفارش', orders > 0 ? '${_number(sales / orders)} تومان' : '۰ تومان', Icons.calculate_outlined, const Color(0xFF8B72E8), 'فروش تقسیم بر تعداد سفارش'),
        _metric('تغییر نسبت به قبل', _percentage(growth), Icons.compare_arrows_rounded, growth >= 0 ? const Color(0xFF39B982) : const Color(0xFFE45B70), 'درصد تغییر فروش'),
      ]),
      const SizedBox(height: 18),
      _sectionCard(
        title: 'تفکیک مبالغ فروش',
        subtitle: 'فقط سفارش‌های تکمیل‌شده؛ بازپرداخت‌ها بر اساس زمان پردازش ثبت می‌شوند',
        icon: Icons.receipt_long_outlined,
        child: Column(children: [
          _financialLine('فروش ناخالص', grossSales, _blue),
          _financialLine('تخفیف‌ها', discounts, const Color(0xFFE9A23B)),
          const Divider(height: 18),
          _financialLine('فروش خالص پس از تخفیف', netSales, const Color(0xFF39B982), strong: true),
          _financialLine('هزینه ارسال', deliveryFees, const Color(0xFF8B72E8)),
          _financialLine('بازپرداخت انجام‌شده (${_number(_num(summary, 'refund_count'))} مورد)', refunds, const Color(0xFFE45B70)),
          const Divider(height: 18),
          _financialLine('خالص پس از بازپرداخت', netAfterRefunds, netAfterRefunds >= 0 ? const Color(0xFF39B982) : const Color(0xFFE45B70), strong: true),
          const SizedBox(height: 8),
          const Text('بازپرداخت‌ها جداگانه نمایش داده می‌شوند؛ ممکن است مربوط به سفارش لغوشده‌ای باشند که در فروش سفارش‌های تکمیل‌شده محاسبه نشده است.', style: TextStyle(color: Color(0xFF8792A8), fontSize: 12)),
        ]),
      ),
      const SizedBox(height: 18),
      _sectionCard(
        title: 'درآمد ثبت‌شده و وجه دریافتی',
        subtitle: 'وجه دریافتی فقط از پرداخت‌هایی محاسبه می‌شود که در جزئیات سفارش ثبت شده‌اند',
        icon: Icons.account_balance_wallet_outlined,
        child: Column(children: [
          _financialLine('درآمد ثبت‌شده سفارش‌های تکمیل‌شده', recordedRevenue, _blue, strong: true),
          _financialLine('وجه واقعاً دریافت‌شده در این بازه', cashReceived, const Color(0xFF39B982), strong: true),
          _financialLine('مانده قابل دریافت سفارش‌های این بازه', receivable, const Color(0xFFE9A23B)),
          const SizedBox(height: 8),
          const Text('سفارش‌های قدیمی که پرداختشان در پنل ثبت نشده، به‌صورت خودکار پرداخت‌شده فرض نمی‌شوند. وجه دریافتی بر اساس تاریخ ثبت پرداخت و مانده بر اساس سفارش‌های تکمیل‌شده در بازه است.', style: TextStyle(color: Color(0xFF8792A8), fontSize: 12)),
        ]),
      ),
      const SizedBox(height: 18),
      _sectionCard(
        title: 'روند فروش خالص',
        subtitle: 'مبالغ محور نمودار به تومان است؛ فروش خالص روزانه پس از کسر تخفیف‌ها',
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
                    final amount = _num(item, 'net_sales') != 0 ? _num(item, 'net_sales') : _num(item, 'amount');
                    return BarChartGroupData(x: entry.key, barRods: [BarChartRodData(toY: amount.toDouble(), width: mobile ? 13 : 22, borderRadius: BorderRadius.circular(7), color: _blue, backDrawRodData: BackgroundBarChartRodData(show: true, toY: chart.map((e) => (_num(e, 'net_sales') != 0 ? _num(e, 'net_sales') : _num(e, 'amount')).toDouble()).fold<double>(0, (a, b) => a > b ? a : b), color: const Color(0xFFF0F4FC)))]);
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
      subtitle: 'فروش تجمعی کل دوره‌ها؛ مستقل از فیلتر تاریخ بالای صفحه',
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
      return _sectionCard(title: 'گزارش مشتریان', subtitle: 'مشتریان دارای سفارش تکمیل‌شده در کل دوره‌ها؛ مستقل از فیلتر تاریخ', icon: Icons.people_alt_outlined,
        child: const _NoData(message: 'گزارش مشتریان هنوز داده‌ای برنگردانده است.'));
    }
    final entries = summary.entries.toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (entries.isNotEmpty)
        _metricGrid(context, MediaQuery.sizeOf(context).width < 640, entries.take(4).map((entry) => _metric(
          _humanize(entry.key), _number(_asNum(entry.value)), Icons.people_outline_rounded, _blue, 'مقدار برگشتی از گزارش مشتریان',
        )).toList()),
      const SizedBox(height: 18),
      _sectionCard(title: 'توزیع مشتریان', subtitle: 'تعداد مشتریان یکتا در هر نوع سفارش؛ ممکن است مشتری در چند گروه باشد', icon: Icons.groups_2_outlined,
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


  Widget _financialTab(BuildContext context, bool mobile, Map<String, dynamic> summary, List<Map<String, dynamic>> chart, bool loading) {
    if (loading && summary.isEmpty) {
      return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
    }
    if (summary.isEmpty) {
      return _sectionCard(title: 'گزارش مالی و سود', subtitle: 'درآمد، هزینه و سود تخمینی', icon: Icons.account_balance_wallet_outlined,
        child: const _NoData(message: 'گزارش مالی در دسترس نیست. اسکریپت گزارش مالی Supabase را اجرا کنید.'));
    }
    final revenue = _asNum(summary['revenue']);
    final stockCost = _asNum(summary['inventory_cost']);
    final wasteCost = _asNum(summary['waste_cost']);
    final expenses = _asNum(summary['operating_expenses']);
    final ingredientPurchases = _asNum(summary['ingredient_purchase_expenses']);
    final profit = _asNum(summary['estimated_profit']);
    final costs = _asNum(summary['total_costs']);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _metricGrid(context, mobile, [
        _metric('درآمد فروش', '${_number(revenue)} تومان', Icons.payments_outlined, _blue, 'فقط سفارش‌های تکمیل‌شده'),
        _metric('مواد مصرف‌شده', '${_number(stockCost)} تومان', Icons.kitchen_outlined, const Color(0xFF8B72E8), 'مواد مصرف‌شده طبق دستور پخت و سفارش'),
        _metric('ضایعات مواد', '${_number(wasteCost)} تومان', Icons.delete_sweep_outlined, const Color(0xFFE45B70), 'ضایعات ثبت‌شده در انبار'),
        _metric('هزینه‌های عملیاتی', '${_number(expenses)} تومان', Icons.receipt_long_outlined, const Color(0xFFE9A23B), 'هزینه‌های ثبت‌شده به‌جز خرید مواد'),
        _metric('سود عملیاتی تخمینی', '${_number(profit)} تومان', Icons.trending_up_rounded, profit >= 0 ? const Color(0xFF39B982) : const Color(0xFFE45B70), 'فروش منهای مواد مصرفی، ضایعات و هزینه‌های عملیاتی'),
      ]),
      const SizedBox(height: 18),
      _sectionCard(title: 'خلاصه مالی', subtitle: 'برآورد مالی در بازه انتخاب‌شده', icon: Icons.account_balance_outlined,
        trailing: Wrap(spacing: 4, children: [
          TextButton.icon(onPressed: () => context.push('/expenses'), icon: const Icon(Icons.list_alt_outlined, size: 18), label: const Text('مدیریت هزینه‌ها')),
          TextButton.icon(onPressed: () => _addExpense(context), icon: const Icon(Icons.add, size: 18), label: const Text('ثبت سریع')),
        ]),
        child: Column(children: [
          _financialLine('درآمد فروش', revenue, const Color(0xFF3977EE)),
          _financialLine('مواد مصرف‌شده در سفارش‌ها', stockCost, const Color(0xFF8B72E8)),
          _financialLine('ضایعات مواد اولیه', wasteCost, const Color(0xFFE45B70)),
          _financialLine('هزینه‌های عملیاتی', expenses, const Color(0xFFE9A23B)),
          _financialLine('خرید مواد ثبت‌شده (جدا از سود)', ingredientPurchases, const Color(0xFF65C99A)),
          const Divider(height: 24),
          _financialLine('مجموع هزینه‌ها', costs, const Color(0xFFE45B70)),
          _financialLine('سود تخمینی', profit, profit >= 0 ? const Color(0xFF39B982) : const Color(0xFFE45B70), strong: true),
          const SizedBox(height: 12),
          Text('حاشیه سود: ${_digits(_asNum(summary['profit_margin_percent']).toStringAsFixed(2))}٪', style: const TextStyle(color: _ink, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('توجه: سود تخمینی بر اساس مواد مصرف‌شده، ضایعات ثبت‌شده و هزینه‌های عملیاتی است. خرید مواد جداگانه نمایش داده می‌شود تا با مصرف و ضایعات دوباره‌شماری نشود.', style: TextStyle(color: Color(0xFF8792A8), fontSize: 12)),
        ])),
      if (chart.isNotEmpty) ...[
        const SizedBox(height: 18),
        _sectionCard(title: 'ترکیب مالی', subtitle: 'مقایسه فروش و هزینه‌های ثبت‌شده', icon: Icons.bar_chart_rounded,
          child: Column(children: chart.map((item) {
            final label = (item['label'] ?? 'شاخص').toString();
            final amount = _asNum(item['amount']);
            final ratio = revenue > 0 ? (amount.abs() / revenue).clamp(0.0, 1.0).toDouble() : 0.0;
            return Padding(padding: const EdgeInsets.only(bottom: 14), child: Column(children: [
              Row(children: [Expanded(child: Text(label, style: const TextStyle(color: _ink, fontWeight: FontWeight.w600))), Text('${_number(amount)} تومان', style: const TextStyle(color: _ink, fontWeight: FontWeight.w700, fontSize: 12))]),
              const SizedBox(height: 7),
              ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: ratio, minHeight: 7, backgroundColor: const Color(0xFFF0F3FA), color: _blue)),
            ]));
          }).toList())),
      ],
    ]);
  }


  Widget _dishProfitTab(BuildContext context, bool mobile, Map<String,dynamic> summary, Map<String,dynamic> data, bool loading) {
    final dishes=(data['dishes'] as List<dynamic>? ?? const []).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
    final daily=(data['daily'] as List<dynamic>? ?? const []).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
    final monthly=(data['monthly'] as List<dynamic>? ?? const []).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
    if(loading && summary.isEmpty) return const Center(child:CircularProgressIndicator());
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      _metricGrid(context,mobile,[
        _metric('فروش خالص غذاها','${_number(_asNum(summary['total_revenue']))} تومان',Icons.payments_outlined,_blue,'پس از تخصیص تخفیف سفارش'),
        _metric('بهای مواد اولیه','${_number(_asNum(summary['total_cost']))} تومان',Icons.kitchen_outlined,const Color(0xFF8B72E8),'بر اساس دستور پخت و قیمت فعلی انبار'),
        _metric('سود ناخالص غذاها','${_number(_asNum(summary['total_profit']))} تومان',Icons.trending_up,const Color(0xFF39B982),'قبل از هزینه‌های عملیاتی'),
      ]),
      const SizedBox(height:16),
      _sectionCard(title:'سودآوری هر غذا',subtitle:'فروش، تعداد، بهای تمام‌شده و سود ناخالص هر محصول',icon:Icons.restaurant_menu_outlined,
        child:dishes.isEmpty?const _NoData(message:'در این بازه فروش تکمیل‌شده‌ای ثبت نشده است.'):Column(children:dishes.map((d){
          final name=(d['product_name']??'غذای نامشخص').toString();
          return ListTile(contentPadding:EdgeInsets.zero,title:Text(name,style:const TextStyle(fontWeight:FontWeight.w700)),
            subtitle:Text('${_digits(_asNum(d['quantity']).toStringAsFixed(0))} عدد · فروش ${_number(_asNum(d['net_revenue']))} · هزینه ${_number(_asNum(d['total_cost']))} تومان'),
            trailing:Text('${_number(_asNum(d['gross_profit']))} تومان',style:TextStyle(fontWeight:FontWeight.w800,color:_asNum(d['gross_profit'])>=0?const Color(0xFF279B70):const Color(0xFFE45B70))));
        }).toList())),
      const SizedBox(height:16),
      _sectionCard(title:'سود روزانه',subtitle:'فروش خالص منهای بهای مواد مصرفی',icon:Icons.calendar_view_day,
        child:daily.isEmpty?const _NoData(message:'داده روزانه‌ای وجود ندارد.'):Column(children:daily.map((r)=>_financialLine((r['date']??'').toString(),_asNum(r['profit']),const Color(0xFF39B982))).toList())),
      const SizedBox(height:16),
      _sectionCard(title:'سود ماهانه',subtitle:'تجمیع فروش و بهای مواد در هر ماه',icon:Icons.calendar_month,
        child:monthly.isEmpty?const _NoData(message:'داده ماهانه‌ای وجود ندارد.'):Column(children:monthly.map((r)=>_financialLine((r['month']??'').toString(),_asNum(r['profit']),const Color(0xFF8B72E8))).toList())),
      const SizedBox(height:8),
      const Text('توجه: سود هر غذا و سود روزانه/ماهانه در این بخش سود ناخالص پس از بهای مواد دستور پخت است؛ هزینه‌های عملیاتی، ضایعات و کسری‌های ثبت‌نشده در این تفکیک محصولی لحاظ نشده‌اند. برای محصول بدون دستور پخت، بهای مواد صفر گزارش می‌شود.',style:TextStyle(fontSize:12,color:Color(0xFF8792A8))),
    ]);
  }

  Future<void> _recordCashClosing(BuildContext context) async {
    final opening=TextEditingController(text:'0'), counted=TextEditingController(), shift=TextEditingController(text:'شیفت اصلی'), note=TextEditingController();
    final form=GlobalKey<FormState>();
    final result=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('ثبت شمارش صندوق'),
      content:Form(key:form,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextFormField(controller:shift,decoration:const InputDecoration(labelText:'نام شیفت'),validator:(v)=>v==null||v.trim().isEmpty?'نام شیفت الزامی است':null),
        TextFormField(controller:opening,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'موجودی نقد ابتدای شیفت (تومان)'),validator:(v)=>_asNum(v)<0?'مبلغ نامعتبر است':null),
        TextFormField(controller:counted,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'وجه نقد شمارش‌شده پایان شیفت (تومان)'),validator:(v)=>_asNum(v)<0?'مبلغ نامعتبر است':null),
        TextFormField(controller:note,decoration:const InputDecoration(labelText:'توضیحات (اختیاری)')),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('انصراف')),
        FilledButton(onPressed:()async{if(!form.currentState!.validate())return;try{
          final now=DateTime.now(); final date='${now.year.toString().padLeft(4,'0')}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
          await SupabaseService.client.rpc('record_cash_register_closing',params:{'p_business_date':date,'p_shift_label':shift.text.trim(),'p_opening_cash':_asNum(opening.text),'p_counted_cash':_asNum(counted.text),'p_note':note.text.trim()});
          if(ctx.mounted)Navigator.pop(ctx,true);
        }catch(_){if(ctx.mounted)ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content:Text('ثبت بستن صندوق ناموفق بود. دسترسی مدیر و اتصال را بررسی کنید.')));}},child:const Text('ثبت شمارش'))]));
    opening.dispose();counted.dispose();shift.dispose();note.dispose();
    if(result==true&&mounted)_fetchReport();
  }

  Widget _paymentReconciliationTab(BuildContext context,bool mobile,Map<String,dynamic> summary,Map<String,dynamic> data,bool loading){
    final methods=(data['methods'] as List<dynamic>? ?? const []).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
    final closings=(data['closings'] as List<dynamic>? ?? const []).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
    if(loading&&summary.isEmpty)return const Center(child:CircularProgressIndicator());
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(mainAxisAlignment:MainAxisAlignment.end,children:[FilledButton.icon(onPressed:()=>_recordCashClosing(context),icon:const Icon(Icons.point_of_sale_outlined),label:const Text('ثبت شمارش صندوق'))]),
      const SizedBox(height:12),
      _metricGrid(context,mobile,[
        _metric('کل دریافتی','${_number(_asNum(summary['total_received']))} تومان',Icons.payments_outlined,_blue,'پرداخت‌های ثبت‌شده و دریافت‌شده'),
        _metric('دریافتی نقدی','${_number(_asNum(summary['cash_received']))} تومان',Icons.money, const Color(0xFF39B982),'فقط روش نقدی'),
        _metric('غیرنقدی','${_number(_asNum(summary['non_cash_received']))} تومان',Icons.credit_card_outlined,const Color(0xFF8B72E8),'کارت‌خوان، کیف پول و سایر روش‌ها'),
      ]),
      const SizedBox(height:16),
      _sectionCard(title:'تفکیک روش‌های پرداخت',subtitle:'جمع مبالغ پرداخت‌های موفق در بازه انتخابی',icon:Icons.account_balance_wallet_outlined,
        child:methods.isEmpty?const _NoData(message:'پرداخت ثبت‌شده‌ای در این بازه وجود ندارد.'):Column(children:methods.map((r)=>_financialLine('${r['payment_method']} · ${_digits(_asNum(r['payment_count']).toStringAsFixed(0))} تراکنش',_asNum(r['amount']),_blue)).toList())),
      const SizedBox(height:16),
      _sectionCard(title:'مغایرت صندوق',subtitle:'مقایسه وجه نقد شمارش‌شده با موجودی مورد انتظار (ابتدای شیفت + پرداخت نقدی)',icon:Icons.fact_check_outlined,
        child:closings.isEmpty?const _NoData(message:'هنوز شمارش صندوقی ثبت نشده است. برای محاسبه مغایرت، پایان شیفت وجه نقد واقعی را ثبت کنید.'):Column(children:closings.map((r){
          final variance=_asNum(r['variance']); final date=(r['business_date']??'').toString(); final shift=(r['shift_label']??'').toString();
          return ListTile(contentPadding:EdgeInsets.zero,title:Text('$date · $shift',style:const TextStyle(fontWeight:FontWeight.w700)),
            subtitle:Text('مورد انتظار: ${_number(_asNum(r['expected_cash']))} · شمارش‌شده: ${_number(_asNum(r['counted_cash']))} تومان'),
            trailing:Text('${variance>0?'+':''}${_number(variance)} تومان',style:TextStyle(fontWeight:FontWeight.w800,color:variance==0?const Color(0xFF279B70):const Color(0xFFE45B70))));
        }).toList())),
    ]);
  }

  Widget _financialLine(String label, num amount, Color color, {bool strong = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(children: [
      Container(width: 9, height: 9, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: TextStyle(color: _ink, fontWeight: strong ? FontWeight.w800 : FontWeight.w500))),
      Text('${_number(amount)} تومان', style: TextStyle(color: _ink, fontWeight: strong ? FontWeight.w800 : FontWeight.w600)),
    ]),
  );

  Future<void> _addExpense(BuildContext context) async {
    final formKey = GlobalKey<FormState>();
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    var selectedCategory = 'other';
    final notesController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ثبت هزینه رستوران'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: titleController, decoration: const InputDecoration(labelText: 'عنوان هزینه'), validator: (v) => (v == null || v.trim().isEmpty) ? 'عنوان را وارد کنید' : null),
            const SizedBox(height: 10),
            TextFormField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مبلغ (تومان)'), validator: (v) => (_asNum(v) <= 0) ? 'مبلغ معتبر وارد کنید' : null),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: selectedCategory,
              decoration: const InputDecoration(labelText: 'دسته‌بندی هزینه'),
              items: const [
                DropdownMenuItem(value: 'personnel', child: Text('حقوق و دستمزد')),
                DropdownMenuItem(value: 'rent', child: Text('اجاره')),
                DropdownMenuItem(value: 'utilities', child: Text('آب، برق و گاز')),
                DropdownMenuItem(value: 'delivery', child: Text('ارسال و پیک')),
                DropdownMenuItem(value: 'marketing', child: Text('بازاریابی')),
                DropdownMenuItem(value: 'maintenance', child: Text('تعمیر و نگهداری')),
                DropdownMenuItem(value: 'ingredients_purchase', child: Text('خرید مواد اولیه')),
                DropdownMenuItem(value: 'other', child: Text('سایر')),
              ],
              onChanged: (value) => selectedCategory = value ?? 'other',
            ),
            const SizedBox(height: 10),
            TextFormField(controller: notesController, maxLines: 2, decoration: const InputDecoration(labelText: 'توضیحات (اختیاری)')),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
          FilledButton(onPressed: () async {
            if (!formKey.currentState!.validate()) return;
            try {
              final userId = SupabaseService.client.auth.currentUser?.id;
              await SupabaseService.client.from('restaurant_expenses').insert({
                'title': titleController.text.trim(),
                'amount': _asNum(amountController.text),
                'category': selectedCategory,
                'notes': notesController.text.trim(),
                'created_by': userId,
              });
              if (dialogContext.mounted) { Navigator.pop(dialogContext, true); }
            } catch (e) {
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(content: Text('ثبت هزینه ناموفق بود. اجرای SQL گزارش مالی و دسترسی مدیر را بررسی کنید.')),
              );
              }
            }
          }, child: const Text('ثبت هزینه')),
        ],
      ),
    );
    titleController.dispose();
    amountController.dispose();
    notesController.dispose();
    if (saved == true && mounted) _fetchReport();
  }

  Widget _inventoryTab(BuildContext context, bool mobile, Map<String, dynamic> summary, List<Map<String, dynamic>> rows, bool loading) {
    if (loading && summary.isEmpty) {
      return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
    }
    if (summary.isEmpty) {
      return _sectionCard(title: 'گزارش انبار', subtitle: 'موجودی، ارزش انبار و مواد کم‌موجود', icon: Icons.inventory_2_outlined,
        child: const _NoData(message: 'گزارش انبار در دسترس نیست. اسکریپت گزارش انبار Supabase را اجرا کنید.'));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _metricGrid(context, mobile, [
        _metric('مواد فعال', _number(_asNum(summary['active_materials'])), Icons.category_outlined, _blue, 'مواد اولیه فعال'),
        _metric('موجودی کم', _number(_asNum(summary['low_stock_materials'])), Icons.warning_amber_rounded, const Color(0xFFE45B70), 'برابر یا کمتر از حد سفارش'),
        _metric('ارزش فعلی انبار', '${_number(_asNum(summary['stock_value']))} تومان', Icons.inventory_2_outlined, const Color(0xFF39B982), 'موجودی × بهای واحد'),
        _metric('مصرف ثبت‌شده', '${_number(_asNum(summary['consumption_cost']))} تومان', Icons.restaurant_outlined, const Color(0xFF8B72E8), 'هزینه مصرف مواد در بازه'),
      ]),
      const SizedBox(height: 18),
      _sectionCard(title: 'گردش مواد اولیه', subtitle: 'خرید، مصرف، ضایعات و برگشت ثبت‌شده در بازه', icon: Icons.swap_vert_rounded,
        child: Column(children: [
          _financialLine('خرید مواد', _asNum(summary['purchases_cost']), _blue),
          _financialLine('مصرف در سفارش‌ها', _asNum(summary['consumption_cost']), const Color(0xFF8B72E8)),
          _financialLine('ضایعات', _asNum(summary['waste_cost']), const Color(0xFFE45B70)),
          _financialLine('برگشت مواد', _asNum(summary['return_cost']), const Color(0xFF39B982)),
        ])),
      const SizedBox(height: 18),
      _sectionCard(title: 'وضعیت مواد اولیه', subtitle: 'ارزش و موجودی فعلی هر ماده', icon: Icons.list_alt_rounded,
        child: rows.isEmpty ? const _NoData(message: 'ماده اولیه‌ای برای نمایش وجود ندارد.') : Column(children: rows.asMap().entries.map((entry) {
          final item = entry.value;
          final low = item['is_low_stock'] == true;
          final name = (item['material_name'] ?? 'بدون نام').toString();
          final unit = (item['unit'] ?? '').toString();
          final quantity = _asNum(item['quantity_on_hand']);
          final value = _asNum(item['stock_value']);
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F3FA)))),
            child: Row(children: [
              Container(width: 38, height: 38, decoration: BoxDecoration(color: low ? const Color(0xFFFFF0F1) : _paleBlue, borderRadius: BorderRadius.circular(12)),
                child: Icon(low ? Icons.warning_amber_rounded : Icons.inventory_2_outlined, color: low ? const Color(0xFFE45B70) : _blue, size: 20)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(color: _ink, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('${_number(quantity)} $unit', style: const TextStyle(color: Color(0xFF8792A8), fontSize: 12)),
              ])),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${_number(value)} تومان', style: const TextStyle(color: _ink, fontWeight: FontWeight.w700, fontSize: 12)),
                if (low) const Text('نیاز به شارژ', style: TextStyle(color: Color(0xFFE45B70), fontSize: 11, fontWeight: FontWeight.w700)),
              ]),
            ]),
          );
        }).toList())),
    ]);
  }

  Widget _metricGrid(BuildContext context, bool mobile, List<Widget> cards) {
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1000 ? 3 : constraints.maxWidth >= 620 ? 2 : 1;
      final ratio = columns == 1 ? 2.1 : 1.65;
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
          ?trailing,
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
