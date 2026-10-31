import 'package:flutter/material.dart';
import '../../../core/services/supabase_service.dart';

class OrderPaymentPanel extends StatefulWidget {
  final String orderId;
  final num orderTotal;
  const OrderPaymentPanel({super.key, required this.orderId, required this.orderTotal});
  @override
  State<OrderPaymentPanel> createState() => _OrderPaymentPanelState();
}

class _OrderPaymentPanelState extends State<OrderPaymentPanel> {
  List<Map<String, dynamic>> rows = [];
  bool loading = true;
  static const methods = {'cash':'نقدی','card_terminal':'کارت‌خوان','online':'آنلاین','wallet':'کیف پول','bank_transfer':'انتقال بانکی','other':'سایر'};
  num amount(Map<String,dynamic> row) => num.tryParse(row['amount']?.toString() ?? '') ?? 0;
  num get paid => rows.where((r)=>r['status']=='received').fold<num>(0,(s,r)=>s+amount(r));
  String money(num n) {
    final grouped = n.round().toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '٬',
    );
    const latin = '0123456789';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    var result = grouped;
    for (var i = 0; i < latin.length; i++) {
      result = result.replaceAll(latin[i], persian[i]);
    }
    return result;
  }

  num? parseMoney(String raw) {
    var normalized = raw.trim();
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    for (var i = 0; i < 10; i++) {
      normalized = normalized.replaceAll(persian[i], '$i');
      normalized = normalized.replaceAll(arabic[i], '$i');
    }
    normalized = normalized
        .replaceAll(',', '')
        .replaceAll('٬', '')
        .replaceAll('٫', '.')
        .replaceAll(' ', '');
    return num.tryParse(normalized);
  }
  @override
  void initState(){super.initState(); load();}
  Future<void> load() async {
    setState(()=>loading=true);
    try {
      final data=await SupabaseService.client.from('order_payments').select('id,amount,payment_method,status').eq('order_id',widget.orderId).order('received_at',ascending:false);
      if(mounted)setState(()=>rows=data.map((e)=>Map<String,dynamic>.from(e)).toList());
    } catch (_) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('دریافت سوابق پرداخت ناموفق بود.')));
    } finally {if(mounted)setState(()=>loading=false);}
  }
  Future<void> addPayment() async {
    final amountCtrl=TextEditingController(); final refCtrl=TextEditingController(); var method='card_terminal';
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,refresh)=>AlertDialog(
      title:const Text('ثبت دریافت وجه'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:amountCtrl,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'مبلغ دریافتی (تومان)')),
        DropdownButton<String>(value:method,items:methods.entries.map((e)=>DropdownMenuItem(value:e.key,child:Text(e.value))).toList(),onChanged:(v)=>refresh(()=>method=v??'card_terminal')),
        TextField(controller:refCtrl,decoration:const InputDecoration(labelText:'شماره پیگیری (اختیاری)')),
      ]),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('انصراف')),
        FilledButton(onPressed:() async {
          final value = parseMoney(amountCtrl.text);
          if (value == null || value <= 0 || value > widget.orderTotal - paid) { ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('مبلغ معتبر به تومان و کمتر یا مساوی مانده سفارش وارد کنید.'))); return; }
          try {
            await SupabaseService.client.rpc('record_order_payment', params: {
              'p_order_id': widget.orderId,
              'p_amount': value,
              'p_payment_method': method,
              'p_reference_number': refCtrl.text.trim().isEmpty ? null : refCtrl.text.trim(),
              'p_note': null,
            });
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (error) {
            await _logPaymentFailure(error);
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('ثبت پرداخت ناموفق بود؛ مانده به تومان و دسترسی مدیر را بررسی کنید.')),
              );
            }
          }
        },child:const Text('ثبت دریافت')),
      ],
    )));
    amountCtrl.dispose();refCtrl.dispose();if(ok==true)await load();
  }
  Future<void> payFromWallet() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('پرداخت از کیف پول'),
        content: const Text('مانده سفارش به‌صورت کامل از کیف پول مشتری کسر و در سوابق پرداخت ثبت می‌شود. ادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأیید پرداخت')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final result = await SupabaseService.client.rpc(
        'pay_order_from_customer_wallet',
        params: {'p_order_id': widget.orderId},
      );
      await load();
      if (mounted) {
        final data = Map<String, dynamic>.from(result as Map);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(data['already_paid'] == true
              ? 'این سفارش قبلاً تسویه شده است.'
              : 'پرداخت کیف پول با موفقیت ثبت شد.'),
        ));
      }
    } catch (error) {
      await _logPaymentFailure(error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('پرداخت کیف پول انجام نشد؛ موجودی، اتصال حساب مشتری و دسترسی مدیر را بررسی کنید.')),
        );
      }
    }
  }

  Future<void> _logPaymentFailure(Object error) async {
    try {
      await SupabaseService.client.rpc('log_admin_payment_failure', params: {
        'p_order_id': widget.orderId,
        // Avoid storing raw server details or credentials in the notification.
        'p_reason': 'خطا هنگام ثبت یا تأیید پرداخت',
      });
    } catch (_) {
      // The original payment error remains the primary failure. Logging is best effort.
    }
  }

  Future<void> voidPayment(String id) async {
    try {await SupabaseService.client.rpc('void_order_payment',params:{'p_payment_id':id});await load();}
    catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('ابطال پرداخت ناموفق بود.')));}
  }
  @override
  Widget build(BuildContext context){
    final due=(widget.orderTotal-paid).clamp(0,double.infinity);
    return Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[const Expanded(child:Text('وضعیت دریافت وجه',style:TextStyle(fontWeight:FontWeight.bold,fontSize:17))),IconButton(onPressed:loading?null:load,icon:const Icon(Icons.refresh))]),
      if(loading)const LinearProgressIndicator(),
      Text('مبلغ سفارش: ${money(widget.orderTotal)} تومان'),
      Text('دریافت‌شده: ${money(paid)} تومان', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
      Text('مانده: ${money(due)} تومان', style: const TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height:8),
      FilledButton.icon(onPressed:loading||due<=0?null:addPayment,icon:const Icon(Icons.add),label:const Text('ثبت دریافت وجه')),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: loading || due <= 0 ? null : payFromWallet,
        icon: const Icon(Icons.account_balance_wallet_outlined),
        label: const Text('تسویه از کیف پول مشتری'),
      ),
      ...rows.map((r) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('${money(amount(r))} تومان · ${methods[r['payment_method']] ?? 'سایر'}'),
        subtitle: Text(r['status'] == 'received' ? 'ثبت‌شده' : 'باطل‌شده'),
        trailing: r['status'] == 'received'
            ? IconButton(icon: const Icon(Icons.undo, color: Colors.red), onPressed: () => voidPayment(r['id'].toString()))
            : null,
      )),
      const Text('پرداخت‌های قدیمی تا زمان ثبت دستی، دریافت‌شده محسوب نمی‌شوند.',style:TextStyle(fontSize:11,color:Colors.grey)),
    ])));
  }
}
