import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/utils/app_error_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/customer_wallet_model.dart';
import '../../../repositories/customer_wallet_repository.dart';

class CustomerWalletsScreen extends StatefulWidget {
  const CustomerWalletsScreen({super.key});
  @override
  State<CustomerWalletsScreen> createState() => _CustomerWalletsScreenState();
}

class _CustomerWalletsScreenState extends State<CustomerWalletsScreen> {
  final _search = TextEditingController();
  late final CustomerWalletRepository _repository;
  late Future<List<CustomerWalletModel>> _future;
  RealtimeChannel? _channel;
  @override
  void initState() {
    super.initState();
    _repository = CustomerWalletRepository(client: SupabaseService.client);
    _future = _repository.getWallets();
    _channel = SupabaseService.client.channel('admin-customer-wallet-live')
      .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'customer_wallets', callback: (_) => _reload())
      .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'customer_wallet_transactions', callback: (_) => _reload())
      .subscribe();
  }
  @override
  void dispose() {
    _search.dispose();
    final channel = _channel;
    if (channel != null) unawaited(SupabaseService.client.removeChannel(channel));
    super.dispose();
  }
  void _reload() {
    if (!mounted) return;
    setState(() => _future = _repository.getWallets(search: _search.text));
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

  String _money(num value) => _persianDigits(
        value.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (_) => '٬',
        ),
      );

  String _formatDateTime(DateTime? value) {
    if (value == null) return '—';
    final date = value.toLocal();
    return _persianDigits(
      '${date.year}/${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}  '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}',
    );
  }

  Future<void> _editBalance(CustomerWalletModel wallet) async {
    final amountController = TextEditingController();
    final reasonController = TextEditingController();
    final key = GlobalKey<FormState>();
    var adding = true;
    final result = await showDialog<({double delta, String reason})>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text('کیف پول ${wallet.customerName}'),
        content: SizedBox(width: 420, child: Form(key: key, child: Column(mainAxisSize: MainAxisSize.min, children: [
          Align(alignment: Alignment.centerRight, child: Text('موجودی فعلی: ${_money(wallet.balance)} تومان', style: const TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(height: AppSizes.md),
          SegmentedButton<bool>(segments: const [
            ButtonSegment(value: true, label: Text('شارژ کیف پول'), icon: Icon(Icons.add_circle_outline)),
            ButtonSegment(value: false, label: Text('کاهش موجودی'), icon: Icon(Icons.remove_circle_outline)),
          ], selected: {adding}, onSelectionChanged: (value) => setDialogState(() => adding = value.first)),
          const SizedBox(height: AppSizes.md),
          TextFormField(controller: amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'مبلغ (تومان)', border: OutlineInputBorder()),
            validator: (value) { final amount = double.tryParse((value ?? '').replaceAll(',', '').trim()); if (amount == null || amount <= 0 || !amount.isFinite) return 'مبلغ معتبر و بزرگ‌تر از صفر وارد کنید.'; if (!adding && amount > wallet.balance) return 'مبلغ کاهش از موجودی فعلی بیشتر است.'; return null; }),
          const SizedBox(height: AppSizes.md),
          TextFormField(controller: reasonController, minLines: 2, maxLines: 3, decoration: const InputDecoration(labelText: 'دلیل تراکنش', border: OutlineInputBorder()), validator: (value) => (value?.trim().isNotEmpty ?? false) ? null : 'نوشتن دلیل الزامی است.'),
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')), FilledButton(onPressed: () {
          if (!key.currentState!.validate()) return;
          final amount = double.parse(amountController.text.replaceAll(',', '').trim());
          Navigator.pop(dialogContext, (delta: adding ? amount : -amount, reason: reasonController.text.trim()));
        }, child: const Text('ثبت تراکنش'))],
      ),
    ));
    amountController.dispose(); reasonController.dispose();
    if (result == null || !mounted) return;
    try {
      await _repository.adjustBalance(userId: wallet.userId, amountDelta: result.delta, reason: result.reason);
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تغییر موجودی و دفتر گردش مالی با موفقیت ثبت شد.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppErrorMessage.from(e))));
    }
  }

  Future<void> _showHistory(CustomerWalletModel wallet) async {
    await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text('گردش کیف پول · ${wallet.customerName}'),
      content: SizedBox(width: 580, child: FutureBuilder<List<CustomerWalletTransactionModel>>(
        future: _repository.getTransactions(wallet.userId), builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox(height: 150, child: Center(child: CircularProgressIndicator()));
          if (snapshot.hasError) return Text(AppErrorMessage.from(snapshot.error!, fallback: 'دریافت گردش کیف پول ناموفق بود. دوباره تلاش کنید.'));
          final transactions = snapshot.data ?? const <CustomerWalletTransactionModel>[];
          if (transactions.isEmpty) return const Text('برای این کیف پول تراکنشی ثبت نشده است.');
          return SizedBox(height: 380, child: ListView.separated(itemCount: transactions.length, separatorBuilder: (_, _) => const Divider(height: 1), itemBuilder: (context, index) {
            final tx = transactions[index];
            final positive = tx.amountDelta > 0;
            final label = switch (tx.type) {'top_up' => 'شارژ کیف پول', 'refund' => 'بازپرداخت', 'order_payment' => 'پرداخت سفارش', _ => 'اصلاح دستی'};
            return ListTile(title: Text(label), subtitle: Text('${tx.reason}\n${_formatDateTime(tx.createdAt)} · موجودی پس از تراکنش: ${_money(tx.balanceAfter)} تومان'), isThreeLine: true,
              trailing: Text('${positive ? '+' : ''}${_money(tx.amountDelta)}', style: TextStyle(color: positive ? Colors.green : Colors.red, fontWeight: FontWeight.bold)));
          }));
        })),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('بستن'))],
    ));
  }

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(AppSizes.md), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Expanded(child: Text('مدیریت کیف پول مشتریان', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold))), IconButton(tooltip: 'به‌روزرسانی', onPressed: _reload, icon: const Icon(Icons.refresh))]),
    const SizedBox(height: AppSizes.sm),
    const Text('این موجودی پولی مستقل از امتیازهای باشگاه مشتریان است. هر تغییر همراه دلیل و رکورد حسابداری ثبت می‌شود.'),
    const SizedBox(height: AppSizes.md),
    TextField(controller: _search, onSubmitted: (_) => _reload(), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), labelText: 'جست‌وجوی نام، تلفن یا ایمیل', suffixIcon: IconButton(onPressed: () { _search.clear(); _reload(); }, icon: const Icon(Icons.clear)), border: const OutlineInputBorder())),
    const SizedBox(height: AppSizes.md),
    Expanded(child: FutureBuilder<List<CustomerWalletModel>>(future: _future, builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(AppErrorMessage.from(snapshot.error!, fallback: 'دریافت فهرست کیف پول‌ها ناموفق بود. دوباره تلاش کنید.'), textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh), label: const Text('تلاش مجدد'))]));
      final wallets = snapshot.data ?? const <CustomerWalletModel>[];
      if (wallets.isEmpty) return const Center(child: Text('کیف پولی برای نمایش وجود ندارد.')); 
      return ListView.separated(itemCount: wallets.length, separatorBuilder: (_, _) => const SizedBox(height: 8), itemBuilder: (context, index) {
        final wallet = wallets[index];
        return Card(child: Padding(padding: const EdgeInsets.all(AppSizes.md), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const CircleAvatar(child: Icon(Icons.account_balance_wallet_outlined)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(wallet.customerName, style: const TextStyle(fontWeight: FontWeight.bold)), Text(wallet.customerPhone.isEmpty ? (wallet.email ?? 'تلفن ثبت نشده') : wallet.customerPhone)])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('${_money(wallet.balance)} تومان', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), const Text('موجودی کیف پول')])]),
          const Divider(),
          Wrap(spacing: 8, runSpacing: 8, children: [FilledButton.icon(onPressed: () => _editBalance(wallet), icon: const Icon(Icons.add_card), label: const Text('شارژ / اصلاح موجودی')), OutlinedButton.icon(onPressed: () => _showHistory(wallet), icon: const Icon(Icons.history), label: const Text('گردش تراکنش‌ها'))]),
        ])));
      });
    })),
  ]));
}
