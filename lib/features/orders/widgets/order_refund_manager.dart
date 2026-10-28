import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/app_card.dart';

class OrderRefundManager extends StatefulWidget {
  const OrderRefundManager({super.key, required this.orderId, required this.status, required this.totalAmount});
  final String orderId;
  final String status;
  final double totalAmount;
  @override
  State<OrderRefundManager> createState() => _OrderRefundManagerState();
}

class _OrderRefundManagerState extends State<OrderRefundManager> {
  final _reason = TextEditingController();
  final _amount = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  bool _busy = false, _loading = true;
  String _method = 'wallet';

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _reason.dispose(); _amount.dispose(); super.dispose(); }

  void _message(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _load() async {
    try {
      final data = await SupabaseService.client.from('order_refunds').select('*').eq('order_id', widget.orderId).order('created_at', ascending: false);
      if (mounted) setState(() => _rows = data.map((e) => Map<String, dynamic>.from(e)).toList());
    } catch (e) { if (mounted) _message('دریافت سوابق ناموفق بود: $e'); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _cancel() async {
    final c = TextEditingController();
    final reason = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('لغو سفارش'),
      content: TextField(controller: c, autofocus: true, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'علت لغو (اجباری)', border: OutlineInputBorder())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
        FilledButton(onPressed: () { if (c.text.trim().isNotEmpty) Navigator.pop(ctx, c.text.trim()); }, child: const Text('ثبت لغو')),
      ],
    ));
    final why = reason;
    c.dispose();
    if (why == null) return;
    setState(() => _busy = true);
    try {
      final rows = await SupabaseService.client.from('orders').update({'status':'cancelled','cancellation_reason':why,'updated_at':DateTime.now().toUtc().toIso8601String()}).eq('id',widget.orderId).neq('status','completed').select('id');
      if (rows.isEmpty) throw Exception('سفارش تکمیل‌شده قابل لغو نیست یا مجوز ندارید.');
      if (mounted) _message('سفارش لغو شد و علت ذخیره شد.');
    } catch(e) { if (mounted) _message('لغو سفارش ناموفق بود: $e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _create() async {
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (_reason.text.trim().isEmpty || amount == null || amount <= 0 || amount > widget.totalAmount) {
      _message('علت را وارد کنید و مبلغ را بین صفر تا مبلغ سفارش بگذارید.'); return;
    }
    setState(() => _busy = true);
    try {
      await SupabaseService.client.from('order_refunds').insert({
        'order_id':widget.orderId, 'amount':amount, 'reason':_reason.text.trim(),
        'refund_method':_method, 'status':'pending',
        'requested_by':SupabaseService.client.auth.currentUser?.id,
      });
      _reason.clear(); _amount.clear();
      if (mounted) _message('درخواست ثبت شد؛ پس از تأیید مدیر، مبلغ به کیف پول واریز می‌شود.');
      await _load();
    } catch(e) { if (mounted) _message('ثبت درخواست ناموفق بود: $e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _setStatus(Map<String,dynamic> row, String status) async {
    setState(() => _busy = true);
    try {
      if (status == 'refunded') {
        if (row['refund_method'] != 'wallet') throw Exception('فقط بازپرداخت کیف پول از این مسیر انجام می‌شود.');
        await SupabaseService.client.rpc('process_order_refund_to_wallet', params: {'p_refund_id':row['id']});
      } else {
        await SupabaseService.client.from('order_refunds').update({
          'status':status, 'processed_by':SupabaseService.client.auth.currentUser?.id,
          'processed_at':DateTime.now().toUtc().toIso8601String(), 'updated_at':DateTime.now().toUtc().toIso8601String(),
        }).eq('id',row['id']);
      }
      if (mounted) _message(status == 'refunded' ? 'مبلغ با موفقیت به کیف پول مشتری واریز شد.' : 'وضعیت درخواست به‌روزرسانی شد.');
      await _load();
    } catch(e) { if (mounted) _message('عملیات ناموفق بود: $e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  String _label(String s) => switch(s) {
    'pending' => 'در انتظار بررسی', 'approved' => 'تأیید شده',
    'processing' => 'در حال انجام', 'refunded' => 'واریز به کیف پول انجام شد',
    'rejected' => 'رد شده', _ => s,
  };

  @override
  Widget build(BuildContext context) => AppCard(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('لغو سفارش و مدیریت بازپرداخت', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      if (!['cancelled','canceled','completed'].contains(widget.status))
        Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(onPressed:_busy ? null : _cancel, icon:const Icon(Icons.cancel_outlined), label:const Text('لغو سفارش و ثبت علت'))),
      const Divider(height:24),
      Text('ثبت درخواست بازپرداخت', style:Theme.of(context).textTheme.titleMedium),
      Text('مبلغ سفارش: ${NumberFormat.decimalPattern().format(widget.totalAmount)} تومان'),
      const SizedBox(height:8),
      TextField(controller:_amount, keyboardType:const TextInputType.numberWithOptions(decimal:true), decoration:const InputDecoration(labelText:'مبلغ بازپرداخت (تومان)',border:OutlineInputBorder())),
      const SizedBox(height:8),
      TextField(controller:_reason, minLines:2, maxLines:3, decoration:const InputDecoration(labelText:'علت بازپرداخت',border:OutlineInputBorder())),
      const SizedBox(height:8),
      DropdownButtonFormField<String>(value:_method, decoration:const InputDecoration(labelText:'روش بازپرداخت',border:OutlineInputBorder()), items:const [
        DropdownMenuItem(value:'wallet',child:Text('کیف پول مشتری')),
        DropdownMenuItem(value:'original_payment',child:Text('روش پرداخت اولیه (نیازمند فرایند جداگانه)')),
      ], onChanged:_busy ? null : (v) { if(v != null) setState(()=>_method=v); }),
      const SizedBox(height:8),
      FilledButton.icon(onPressed:_busy ? null : _create, icon:const Icon(Icons.add_card), label:const Text('ثبت درخواست')),
      const Divider(height:24),
      Text('سوابق بازپرداخت', style:Theme.of(context).textTheme.titleMedium),
      if (_loading) const LinearProgressIndicator(),
      if (!_loading && _rows.isEmpty) const Text('هنوز بازپرداختی ثبت نشده است.'),
      ..._rows.map((row) {
        final status = (row['status'] ?? 'pending').toString();
        return ListTile(contentPadding:EdgeInsets.zero,
          title:Text('${NumberFormat.decimalPattern().format((row['amount'] as num?)?.toDouble() ?? 0)} تومان • ${_label(status)}'),
          subtitle:Text('${row['reason']} • ${row['refund_method']}'),
          trailing:PopupMenuButton<String>(enabled:!_busy && status != 'refunded' && status != 'rejected',
            onSelected:(v)=>_setStatus(row,v), itemBuilder:(_)=>const [
              PopupMenuItem(value:'approved',child:Text('تأیید')),
              PopupMenuItem(value:'processing',child:Text('در حال انجام')),
              PopupMenuItem(value:'refunded',child:Text('واریز به کیف پول')),
              PopupMenuItem(value:'rejected',child:Text('رد درخواست')),
            ]),
        );
      }),
    ],
  ));
}
