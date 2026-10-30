import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/supabase_service.dart';

class InventoryMaterialReportManager extends StatefulWidget {
  const InventoryMaterialReportManager({super.key});

  @override
  State<InventoryMaterialReportManager> createState() =>
      _InventoryMaterialReportManagerState();
}

class _InventoryMaterialReportManagerState
    extends State<InventoryMaterialReportManager> {
  final _client = SupabaseService.client;
  late DateTimeRange _range;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(
      start: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29)),
      end: DateTime(now.year, now.month, now.day),
    );
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final start = DateTime(_range.start.year, _range.start.month, _range.start.day);
      final endExclusive = DateTime(_range.end.year, _range.end.month, _range.end.day)
          .add(const Duration(days: 1));
      final raw = await _client.rpc(
        'get_inventory_material_activity_report',
        params: {
          'p_start_date': start.toUtc().toIso8601String(),
          'p_end_date': endExclusive.toUtc().toIso8601String(),
        },
      );
      final data = Map<String, dynamic>.from(raw as Map);
      final chart = data['chart_data'] as List? ?? const [];
      if (!mounted) return;
      setState(() {
        _rows = chart.map((row) => Map<String, dynamic>.from(row as Map)).toList();
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _digits(Object? value) {
    const latin = '0123456789';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    var result = value?.toString() ?? '۰';
    for (var i = 0; i < latin.length; i++) {
      result = result.replaceAll(latin[i], persian[i]);
    }
    return result;
  }

  num _number(dynamic value) =>
      value is num ? value : num.tryParse(value?.toString() ?? '') ?? 0;

  String _quantity(dynamic value) {
    final number = _number(value).toDouble();
    final formatted = number.toStringAsFixed(number == number.truncateToDouble() ? 0 : 3)
        .replaceAll('.', '٫');
    return _digits(formatted);
  }

  String _money(dynamic value) => _digits(
        _number(value).toStringAsFixed(0).replaceAllMapped(
              RegExp(r'\\B(?=(\\d{3})+(?!\\d))'),
              (_) => '٬',
            ),
      );

  String _unit(dynamic value) => const {
        'g': 'گرم',
        'kg': 'کیلوگرم',
        'ml': 'میلی‌لیتر',
        'l': 'لیتر',
        'unit': 'عدد',
        'pack': 'بسته',
        'box': 'جعبه',
      }[value?.toString()] ?? 'واحد';

  Widget _metric(BuildContext context, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .35),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final selected = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    initialDateRange: _range,
                    helpText: 'انتخاب بازه گزارش',
                  );
                  if (selected != null && mounted) {
                    setState(() => _range = selected);
                    unawaited(_load());
                  }
                },
                icon: const Icon(Icons.date_range),
                label: Text(
                  '${_digits(_range.start.toIso8601String().substring(0, 10))} تا '
                  '${_digits(_range.end.toIso8601String().substring(0, 10))}',
                ),
              ),
              FilledButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
                label: const Text('به‌روزرسانی'),
              ),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'گزارش بارگذاری نشد: $_error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: _rows.isEmpty && !_loading
              ? const Center(child: Text('در این بازه اطلاعاتی وجود ندارد.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final row = _rows[index];
                    final unit = _unit(row['stock_unit']);
                    return Card(
                      child: ExpansionTile(
                        title: Text(
                          '${row['material_name'] ?? 'ماده اولیه'}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          'موجودی فعلی: ${_quantity(row['current_stock'])} $unit · '
                          'ارزش موجودی: ${_money(row['current_stock_value'])} تومان',
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: Column(
                              children: [
                                Row(children: [
                                  _metric(context, 'خرید در بازه', '${_quantity(row['purchased_quantity'])} $unit'),
                                  const SizedBox(width: 8),
                                  _metric(context, 'هزینه خرید', '${_money(row['purchase_cost'])} تومان'),
                                ]),
                                const SizedBox(height: 8),
                                Row(children: [
                                  _metric(context, 'مصرف', '${_quantity(row['consumed_quantity'])} $unit'),
                                  const SizedBox(width: 8),
                                  _metric(context, 'بهای مصرف', '${_money(row['consumption_cost'])} تومان'),
                                ]),
                                const SizedBox(height: 8),
                                Row(children: [
                                  _metric(context, 'ضایعات', '${_quantity(row['waste_quantity'])} $unit'),
                                  const SizedBox(width: 8),
                                  _metric(context, 'هزینه ضایعات', '${_money(row['waste_cost'])} تومان'),
                                ]),
                                const SizedBox(height: 8),
                                Row(children: [
                                  _metric(context, 'مرجوعی', '${_quantity(row['return_quantity'])} $unit'),
                                  const SizedBox(width: 8),
                                  _metric(context, 'بهای واحد فعلی', '${_money(row['unit_cost'])} تومان / $unit'),
                                ]),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
