import 'package:flutter/material.dart';
import '../../../core/services/supabase_service.dart';

class MarketingEffectivenessTab extends StatefulWidget {
  const MarketingEffectivenessTab({super.key, required this.startDate, required this.endDate});
  final DateTime startDate;
  final DateTime endDate;

  @override
  State<MarketingEffectivenessTab> createState() => _MarketingEffectivenessTabState();
}

class _MarketingEffectivenessTabState extends State<MarketingEffectivenessTab> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _campaigns = [];

  @override
  void initState() { super.initState(); _load(); }

  @override
  void didUpdateWidget(covariant MarketingEffectivenessTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startDate != widget.startDate || oldWidget.endDate != widget.endDate) _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await SupabaseService.client.rpc('admin_get_sms_campaign_effectiveness', params: {
        'p_start': widget.startDate.toUtc().toIso8601String(),
        'p_end': widget.endDate.toUtc().toIso8601String(),
      });
      final data = Map<String, dynamic>.from(result as Map);
      if (!mounted) return;
      setState(() {
        _summary = Map<String, dynamic>.from(data['summary'] as Map? ?? {});
        _campaigns = (data['campaigns'] as List? ?? const []).whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e)).toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'دریافت گزارش اثربخشی ناموفق بود: $e');
    } finally { if (mounted) setState(() => _loading = false); }
  }

  num _n(Map<String, dynamic> map, String key) {
    final v = map[key];
    return v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;
  }

  String _digits(Object? value) {
    const a = '0123456789', b = '۰۱۲۳۴۵۶۷۸۹';
    var s = value?.toString() ?? '۰';
    for (var i = 0; i < a.length; i++) { s = s.replaceAll(a[i], b[i]); }
    return s;
  }

  String _money(Object? value) {
    final n = value is num ? value : num.tryParse(value?.toString() ?? '') ?? 0;
    final s = n.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '٬');
    return '${_digits(s)} تومان';
  }

  Widget _metric(String title, Object? value, IconData icon) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE5EBF7))),
    child: Row(children: [
      Icon(icon, color: const Color(0xFF3977EE)),
      const SizedBox(width: 9),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value?.toString() ?? '۰', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF14264B))),
        Text(title, style: const TextStyle(fontSize: 11, color: Color(0xFF75819A))),
      ])),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading && _campaigns.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _campaigns.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!),
        const SizedBox(height: 10),
        FilledButton(onPressed: _load, child: const Text('تلاش دوباره')),
      ]));
    }
    final roi = _summary['roi_percent'];
    final metrics = <Widget>[
      _metric('کمپین‌ها', _digits(_summary['campaign_count']), Icons.campaign_outlined),
      _metric('گیرندگان', _digits(_summary['recipients']), Icons.people_outline),
      _metric('کلیک‌کنندگان یکتا', _digits(_summary['unique_clickers']), Icons.ads_click),
      _metric('سفارش منتسب', _digits(_summary['attributed_orders']), Icons.shopping_bag_outlined),
      _metric('درآمد سفارش', _money(_summary['order_revenue']), Icons.payments_outlined),
      _metric('بهای تمام‌شده مواد', _money(_summary['cogs']), Icons.inventory_2_outlined),
      _metric('هزینه کمپین', _money(_n(_summary, 'sms_cost') + _n(_summary, 'other_campaign_cost')), Icons.receipt_long_outlined),
      _metric('سود منتسب', _money(_summary['net_profit']), Icons.account_balance_wallet_outlined),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      Row(children: [
        const Expanded(child: Text('اثربخشی کمپین‌های پیامکی و تخفیف‌ها',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF14264B)))),
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
      ]),
      const Text('انتساب بر اساس کلیک ثبت‌شده یا کد تخفیف؛ سود از درآمد پس از تخفیف، بازپرداخت، بهای مواد و هزینه کمپین محاسبه می‌شود.',
        style: TextStyle(fontSize: 12, color: Color(0xFF75819A))),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, c) => GridView.count(
        crossAxisCount: c.maxWidth > 850 ? 4 : c.maxWidth > 520 ? 2 : 1,
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: c.maxWidth > 520 ? 2.3 : 4,
        crossAxisSpacing: 9, mainAxisSpacing: 9, children: metrics,
      )),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
        const Expanded(child: Text('ROI کل', style: TextStyle(fontWeight: FontWeight.w700))),
        Text(roi == null ? 'هزینه کمپین ثبت نشده' : '${_digits((roi as num).toStringAsFixed(1))}٪',
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFF18A879))),
      ]))),
      const SizedBox(height: 12),
      const Text('جزئیات کمپین‌ها', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      if (_campaigns.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('در این بازه کمپینی ثبت نشده است.'))),
      ..._campaigns.map((c) {
        final campaignRoi = c['roi_percent'];
        final profit = _n(c, 'net_profit');
        return Card(margin: const EdgeInsets.only(bottom: 9), child: Padding(
          padding: const EdgeInsets.all(13), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text((c['name'] ?? 'کمپین').toString(), style: const TextStyle(fontWeight: FontWeight.w800))),
              Text(campaignRoi == null ? 'ROI —' : 'ROI ${_digits((campaignRoi as num).toStringAsFixed(1))}٪',
                style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF18A879))),
            ]),
            if (c['discount_code'] != null) Text('کد تخفیف: ${c['discount_code']}'),
            const SizedBox(height: 8),
            Wrap(spacing: 14, runSpacing: 7, children: [
              Text('ارسال پذیرفته‌شده: ${_digits(c['sent_count'])}'),
              Text('کلیک یکتا: ${_digits(c['unique_clickers'])}'),
              Text('سفارش: ${_digits(c['attributed_orders'])}'),
              Text('خرید با کد: ${_digits(c['coupon_orders'])}'),
              Text('خرید از لینک: ${_digits(c['link_orders'])}'),
            ]),
            const Divider(),
            Row(children: [
              const Expanded(child: Text('سود منتسب', style: TextStyle(fontWeight: FontWeight.w700))),
              Text(_money(profit), style: TextStyle(fontWeight: FontWeight.w900,
                color: profit >= 0 ? const Color(0xFF18A879) : const Color(0xFFE45B70))),
            ]),
          ]),
        ));
      }),
      const Padding(padding: EdgeInsets.only(top: 8), child: Text(
        'ارسال پذیرفته‌شده به معنی پذیرش توسط درگاه است، نه تحویل قطعی به گوشی. ROI بر اساس هزینه‌های ثبت‌شده محاسبه می‌شود؛ هزینه‌های عملیاتی تخصیص‌نیافته به سفارش در آن نیست و اثبات‌کننده فروش افزایشی نسبت به گروه کنترل هم نیست.',
        style: TextStyle(fontSize: 11, color: Color(0xFF75819A)))),
    ]);
  }
}
