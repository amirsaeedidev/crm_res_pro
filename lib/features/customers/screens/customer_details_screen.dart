import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/app_error_message.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_loading.dart';
import '../../../models/order_model.dart';
import '../../../models/user_model.dart';
import '../../../repositories/customers_repository.dart';
import '../../../repositories/orders_repository.dart';
import '../../../core/services/supabase_service.dart';

class CustomerDetailsScreen extends StatefulWidget {
  final String customerId;
  const CustomerDetailsScreen({super.key, required this.customerId});
  @override
  State<CustomerDetailsScreen> createState() => _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends State<CustomerDetailsScreen> {
  late final CustomersRepository _customersRepository;
  late final OrdersRepository _ordersRepository;
  late Future<UserModel> _customerFuture;
  late Future<List<OrderModel>> _ordersFuture;
  late Future<List<Map<String, dynamic>>> _addressesFuture;
  late Future<Map<String, dynamic>?> _walletFuture;
  late Future<List<Map<String, dynamic>>> _transactionsFuture;
  late Future<List<Map<String, dynamic>>> _cashWalletTransactionsFuture;
  late Future<Map<String, dynamic>?> _cashWalletFuture;

  @override
  void initState() {
    super.initState();
    _customersRepository = CustomersRepository();
    _ordersRepository = OrdersRepository();
    _reloadFutures();
  }

  void _reloadFutures() {
    _customerFuture = _customersRepository.getCustomerById(widget.customerId);
    _ordersFuture = _ordersRepository.getOrdersForCustomer(widget.customerId);
    _addressesFuture = _customersRepository.getCustomerAddresses(widget.customerId);
    _walletFuture = _customersRepository.getCustomerWallet(widget.customerId);
    _transactionsFuture = _customersRepository.getCustomerWalletTransactions(widget.customerId);
    _cashWalletFuture = _loadCashWallet();
    _cashWalletTransactionsFuture = _loadCashWalletTransactions();
  }

  void _refresh() => setState(_reloadFutures);

  String _statusLabel(String value) => switch (value) {
    'pending' => 'در انتظار',
    'confirmed' => 'تأیید شده',
    'preparing' => 'در حال آماده‌سازی',
    'ready' => 'آماده',
    'out_for_delivery' => 'در مسیر ارسال',
    'completed' => 'تکمیل‌شده',
    'cancelled' => 'لغوشده',
    _ => 'نامشخص',
  };

  String _customerStatusLabel(String value) => switch (value.toLowerCase()) {
    'active' => 'فعال',
    'inactive' => 'غیرفعال',
    'blocked' => 'مسدود',
    'pending' => 'در انتظار تأیید',
    _ => 'نامشخص',
  };

  String _persianDigits(String value) {
    const latin = '0123456789';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    var result = value;
    for (var i = 0; i < latin.length; i++) {
      result = result.replaceAll(latin[i], persian[i]);
    }
    return result;
  }

  String _formatDate(DateTime value) {
    final date = value.toLocal();
    return _persianDigits(
      '${date.year}/${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}  '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}',
    );
  }

  String _displayDate(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null ? '—' : _formatDate(date);
  }

  String _money(num amount) => _persianDigits(
        amount.round().toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (_) => '٬',
        ),
      );


  Future<Map<String, dynamic>?> _loadCashWallet() async {
    final rows = await SupabaseService.client
        .from('customer_wallets_view')
        .select('*')
        .eq('user_id', widget.customerId)
        .maybeSingle();
    return rows == null ? null : Map<String, dynamic>.from(rows);
  }

  Future<List<Map<String, dynamic>>> _loadCashWalletTransactions() async {
    final rows = await SupabaseService.client
        .from('customer_wallet_transactions')
        .select('id,amount_delta,balance_after,transaction_type,reason,created_at,order_id')
        .eq('user_id', widget.customerId)
        .order('created_at', ascending: false)
        .limit(30);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  String _cashTypeLabel(String type) => switch (type) {
    'top_up' => 'شارژ کیف پول',
    'order_payment' => 'پرداخت سفارش',
    'refund' => 'بازپرداخت',
    'adjustment' => 'اصلاح موجودی',
    _ => type.isEmpty ? 'تراکنش' : type,
  };

  Future<void> _editCustomer(UserModel customer) async {
    final firstName = TextEditingController(text: customer.firstName ?? '');
    final lastName = TextEditingController(text: customer.lastName ?? '');
    final phone = TextEditingController(text: customer.phone ?? '');
    var marketingOptIn = customer.marketingSmsOptIn;
    var status = customer.status;
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('ویرایش اطلاعات مشتری'),
        content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: firstName, decoration: const InputDecoration(labelText: 'نام', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: lastName, decoration: const InputDecoration(labelText: 'نام خانوادگی', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'شماره تلفن', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(initialValue: status, decoration: const InputDecoration(labelText: 'وضعیت حساب', border: OutlineInputBorder()),
            items: const [DropdownMenuItem(value: 'active', child: Text('فعال')), DropdownMenuItem(value: 'inactive', child: Text('غیرفعال')), DropdownMenuItem(value: 'blocked', child: Text('مسدود'))],
            onChanged: (value) { if (value != null) setDialogState(() => status = value); }),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('رضایت برای دریافت پیامک تبلیغاتی'), subtitle: const Text('پیام تبلیغاتی فقط برای مشتریان دارای رضایت صف می‌شود.'), value: marketingOptIn, onChanged: (value) => setDialogState(() => marketingOptIn = value)),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, {
            'first_name': firstName.text.trim(), 'last_name': lastName.text.trim(), 'phone': phone.text.trim(),
            'status': status, 'marketing_sms_opt_in': marketingOptIn,
          }), child: const Text('ذخیره')),
        ],
      )),
    );
    firstName.dispose(); lastName.dispose(); phone.dispose();
    if (data == null || !mounted) return;
    try {
      await _customersRepository.updateCustomer(widget.customerId, data);
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اطلاعات مشتری از دیتابیس به‌روزرسانی شد.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppErrorMessage.from(e, fallback: 'ویرایش اطلاعات مشتری ناموفق بود. دوباره تلاش کنید.'))));
    }
  }

  Future<void> _adjustPoints(Map<String, dynamic> wallet) async {
    final points = TextEditingController();
    final reason = TextEditingController();
    var isAdding = true;
    final current = (wallet['total_points'] as num? ?? 0).toInt();
    final result = await showDialog<({int delta, String reason})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('اصلاح موجودی کیف امتیاز'),
        content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('موجودی فعلی: ${_persianDigits(current.toString())} امتیاز'),
          const SizedBox(height: 12),
          SegmentedButton<bool>(segments: const [ButtonSegment(value: true, label: Text('افزایش'), icon: Icon(Icons.add)), ButtonSegment(value: false, label: Text('کاهش'), icon: Icon(Icons.remove))], selected: {isAdding}, onSelectionChanged: (s) => setDialogState(() => isAdding = s.first)),
          const SizedBox(height: 12),
          TextField(controller: points, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'تعداد امتیاز', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: reason, minLines: 2, maxLines: 3, decoration: const InputDecoration(labelText: 'دلیل اصلاح (الزامی)', border: OutlineInputBorder())),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')), FilledButton(onPressed: () {
          final n = int.tryParse(points.text.trim());
          if (n == null || n <= 0 || reason.text.trim().isEmpty || (!isAdding && n > current)) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعداد امتیاز و دلیل را معتبر وارد کنید.')));
            return;
          }
          Navigator.pop(dialogContext, (delta: n * (isAdding ? 1 : -1), reason: reason.text.trim()));
        }, child: const Text('ثبت تراکنش'))],
      )),
    );
    points.dispose(); reason.dispose();
    if (result == null || !mounted) return;
    try {
      final newBalance = await _customersRepository.adjustCustomerPoints(userId: widget.customerId, pointsDelta: result.delta, description: result.reason);
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('موجودی جدید: ${_persianDigits(newBalance.toString())} امتیاز. تراکنش ثبت شد.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppErrorMessage.from(e, fallback: 'اصلاح امتیاز مشتری ناموفق بود. دوباره تلاش کنید.'))));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.getBackground(context),
    appBar: AppBar(title: const Text('مدیریت کامل مشتری'), backgroundColor: AppColors.getSurface(context), foregroundColor: AppColors.getPrimaryText(context), actions: [IconButton(onPressed: _refresh, tooltip: 'به‌روزرسانی', icon: const Icon(Icons.refresh))]),
    body: FutureBuilder<UserModel>(
      future: _customerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: AppLoading());
        if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(AppSizes.lg), child: Text(AppErrorMessage.from(snapshot.error!, fallback: 'دریافت اطلاعات مشتری ناموفق بود. دوباره تلاش کنید.'), textAlign: TextAlign.center)));
        final customer = snapshot.data;
        if (customer == null) return const Center(child: Text('مشتری پیدا نشد.'));
        return ListView(padding: const EdgeInsets.all(AppSizes.lg), children: [
          AppCard(child: Row(children: [
            CircleAvatar(radius: 28, backgroundColor: AppColors.primary, child: Text(customer.fullName.isEmpty ? '?' : customer.fullName.characters.first, style: const TextStyle(color: Colors.white, fontSize: 20))),
            const SizedBox(width: AppSizes.md),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(customer.fullName, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              if (customer.email.isNotEmpty) Text(customer.email),
              if ((customer.phone ?? '').isNotEmpty) Text(customer.phone!),
              Text('وضعیت: ${_customerStatusLabel(customer.status)} • تاریخ ثبت‌نام: ${_formatDate(customer.createdAt)}'),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [Chip(label: Text(customer.marketingSmsOptIn ? 'رضایت پیامک تبلیغاتی' : 'بدون رضایت تبلیغاتی')), Chip(label: Text('شناسه ${customer.id.substring(0, customer.id.length > 8 ? 8 : customer.id.length)}'))]),
            ])),
            IconButton(tooltip: 'ویرایش اطلاعات', onPressed: () => _editCustomer(customer), icon: const Icon(Icons.edit_outlined)),
          ])),
          const SizedBox(height: AppSizes.lg),
          Text('کیف پول و امتیاز وفاداری', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSizes.sm),
          FutureBuilder<Map<String, dynamic>?>(future: _walletFuture, builder: (context, walletSnapshot) {
            if (walletSnapshot.connectionState == ConnectionState.waiting) return const AppCard(child: LinearProgressIndicator());
            if (walletSnapshot.hasError) return AppCard(child: Text(AppErrorMessage.from(walletSnapshot.error!, fallback: 'دریافت کیف امتیاز مشتری ناموفق بود. دوباره تلاش کنید.')));
            final wallet = walletSnapshot.data;
            if (wallet == null) return const AppCard(child: Text('برای این مشتری کیف امتیاز ثبت نشده است.'));
            final balance = (wallet['total_points'] as num? ?? 0).toInt();
            return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [const Icon(Icons.account_balance_wallet_outlined, size: 30), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${_persianDigits(balance.toString())} امتیاز', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)), Text('آخرین به‌روزرسانی: ${_displayDate(wallet['updated_at'])}', style: Theme.of(context).textTheme.bodySmall)])), FilledButton.icon(onPressed: () => _adjustPoints(wallet), icon: const Icon(Icons.tune), label: const Text('اصلاح موجودی'))]),
              const Divider(height: 24),
              Text('گردش آخرین تراکنش‌ها', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              FutureBuilder<List<Map<String, dynamic>>>(future: _transactionsFuture, builder: (context, transactionsSnapshot) {
                if (transactionsSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (transactionsSnapshot.hasError) return Text(AppErrorMessage.from(transactionsSnapshot.error!, fallback: 'دریافت گردش امتیاز ناموفق بود. دوباره تلاش کنید.'));
                final transactions = transactionsSnapshot.data ?? const <Map<String, dynamic>>[];
                if (transactions.isEmpty) return const Text('تراکنشی ثبت نشده است.');
                return Column(children: transactions.take(15).map((tx) {
                  final n = (tx['points'] as num? ?? 0).toInt();
                  final type = switch ((tx['transaction_type'] ?? '').toString()) {'earned' => 'کسب', 'redeemed' => 'مصرف', 'adjusted' => 'اصلاح دستی', _ => 'سایر'};
                  return ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text('$type • ${_persianDigits(n > 0 ? '+$n' : '$n')} امتیاز'), subtitle: Text('${tx['description'] ?? ''}\n${_displayDate(tx['created_at'])}'), isThreeLine: true, trailing: Text(_persianDigits(n >= 0 ? '+$n' : '$n'), style: TextStyle(color: n >= 0 ? Colors.green : Colors.red, fontWeight: FontWeight.bold)));
                }).toList());
              }),
            ]));
          }),

          const SizedBox(height: AppSizes.lg),
          Text('کیف پول نقدی مشتری', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSizes.sm),
          FutureBuilder<Map<String, dynamic>?>(
            future: _cashWalletFuture,
            builder: (context, cashSnapshot) {
              if (cashSnapshot.connectionState == ConnectionState.waiting) return const AppCard(child: LinearProgressIndicator());
              if (cashSnapshot.hasError) return AppCard(child: Text(AppErrorMessage.from(cashSnapshot.error!, fallback: 'دریافت موجودی کیف پول ناموفق بود.')));
              final wallet = cashSnapshot.data;
              if (wallet == null) return const AppCard(child: Text('برای این مشتری کیف پول نقدی ایجاد نشده است.'));
              final balance = (wallet['balance'] as num? ?? 0).toDouble();
              return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.account_balance_wallet_outlined, size: 30),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_money(balance)} تومان', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    Text('موجودی واقعی کیف پول', style: Theme.of(context).textTheme.bodySmall),
                  ])),
                  TextButton.icon(onPressed: () => context.push('/wallets'), icon: const Icon(Icons.open_in_new), label: const Text('مدیریت کیف پول')),
                ]),
                const Divider(height: 24),
                Text('گردش مالی کیف پول', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _cashWalletTransactionsFuture,
                  builder: (context, txSnapshot) {
                    if (txSnapshot.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
                    if (txSnapshot.hasError) return Text(AppErrorMessage.from(txSnapshot.error!, fallback: 'دریافت گردش کیف پول ناموفق بود.'));
                    final txs = txSnapshot.data ?? const <Map<String, dynamic>>[];
                    if (txs.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('تراکنش مالی ثبت نشده است.'));
                    return Column(children: txs.map((tx) {
                      final delta = (tx['amount_delta'] as num? ?? 0).toDouble();
                      final positive = delta >= 0;
                      final orderId = tx['order_id']?.toString();
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(positive ? Icons.add_circle_outline : Icons.remove_circle_outline, color: positive ? Colors.green : Colors.red),
                        title: Text('${_cashTypeLabel((tx['transaction_type'] ?? '').toString())} · ${positive ? '+' : ''}${_money(delta)} تومان'),
                        subtitle: Text('${(tx['reason'] ?? '').toString()}\n${_displayDate(tx['created_at'])}${orderId == null ? '' : '\nسفارش: ${orderId.substring(0, orderId.length > 8 ? 8 : orderId.length)}'}'),
                        isThreeLine: true,
                        trailing: Text('${_money((tx['balance_after'] as num? ?? 0).toDouble())} ت', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      );
                    }).toList());
                  },
                ),
              ]));
            },
          ),
          const SizedBox(height: AppSizes.lg),
          Text('آدرس‌های ثبت‌شده', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSizes.sm),
          FutureBuilder<List<Map<String, dynamic>>>(future: _addressesFuture, builder: (context, addressSnapshot) {
            if (addressSnapshot.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
            if (addressSnapshot.hasError) return AppCard(child: Text(AppErrorMessage.from(addressSnapshot.error!, fallback: 'دریافت آدرس‌های مشتری ناموفق بود. دوباره تلاش کنید.')));
            final addresses = addressSnapshot.data ?? const <Map<String, dynamic>>[];
            if (addresses.isEmpty) return const AppCard(child: Text('آدرسی برای این مشتری ثبت نشده است.'));
            return Column(children: addresses.map((address) => AppCard(margin: const EdgeInsets.only(bottom: AppSizes.sm), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Expanded(child: Text((address['title'] ?? 'آدرس').toString(), style: const TextStyle(fontWeight: FontWeight.bold))), if (address['is_default'] == true) const Chip(label: Text('پیش‌فرض'))]),
              if ((address['recipient_name'] ?? '').toString().isNotEmpty) Text('گیرنده: ${address['recipient_name']}'),
              if ((address['phone'] ?? '').toString().isNotEmpty) Text('تلفن: ${_persianDigits((address['phone'] ?? '').toString())}'),
              Text((address['address_line'] ?? '').toString()),
              if ((address['postal_code'] ?? '').toString().isNotEmpty) Text('کد پستی: ${_persianDigits((address['postal_code'] ?? '').toString())}'),
            ]))).toList());
          }),
          const SizedBox(height: AppSizes.lg),
          Text('سفارش‌های واقعی مشتری', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSizes.sm),
          FutureBuilder<List<OrderModel>>(future: _ordersFuture, builder: (context, ordersSnapshot) {
            if (ordersSnapshot.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
            if (ordersSnapshot.hasError) return AppCard(child: Text(AppErrorMessage.from(ordersSnapshot.error!, fallback: 'دریافت سفارش‌های مشتری ناموفق بود. دوباره تلاش کنید.')));
            final orders = ordersSnapshot.data ?? const <OrderModel>[];
            if (orders.isEmpty) return const AppCard(child: Text('سفارشی برای این مشتری ثبت نشده است.'));
            return Column(children: orders.map((order) => AppCard(margin: const EdgeInsets.only(bottom: AppSizes.sm), child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('شناسه سفارش: ${order.id.substring(0, order.id.length > 8 ? 8 : order.id.length)}', style: const TextStyle(fontWeight: FontWeight.bold)), Text(_formatDate(order.createdAt)), Text('وضعیت: ${_statusLabel(order.status)}')])),
              Text('${_money(order.totalAmount)} تومان', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            ]))).toList());
          }),
        ]);
      },
    ),
  );
}
