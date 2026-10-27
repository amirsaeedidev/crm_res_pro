import 'package:flutter/material.dart';
import '../../../core/utils/app_error_message.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/loyalty_models.dart';
import '../../../repositories/loyalty_repository.dart';

class LoyaltyScreen extends StatefulWidget {
  const LoyaltyScreen({super.key});

  @override
  State<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends State<LoyaltyScreen> {
  final _searchController = TextEditingController();
  late final LoyaltyRepository _repository;
  late Future<List<LoyaltyWalletModel>> _walletsFuture;

  @override
  void initState() {
    super.initState();
    _repository = LoyaltyRepository(client: SupabaseService.client);
    _walletsFuture = _repository.getWallets();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _walletsFuture = _repository.getWallets(search: _searchController.text));
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

  String _number(int value) => _persianDigits(
        value.toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (_) => '٬',
        ),
      );

  String _formatDateTime(DateTime value) {
    final date = value.toLocal();
    return _persianDigits(
      '${date.year}/${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}  '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}',
    );
  }

  Future<void> _showTransactions(LoyaltyWalletModel wallet) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('گردش امتیاز ${wallet.customerName.isEmpty ? wallet.customerPhone : wallet.customerName}'),
        content: SizedBox(
          width: 560,
          child: FutureBuilder<List<LoyaltyTransactionModel>>(
            future: _repository.getTransactions(wallet.id),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
              }
              if (snapshot.hasError) return Text(AppErrorMessage.from(snapshot.error!, fallback: 'دریافت گردش امتیاز ناموفق بود. دوباره تلاش کنید.'));
              final transactions = snapshot.data ?? const <LoyaltyTransactionModel>[];
              if (transactions.isEmpty) return const Text('تراکنشی برای این کیف امتیاز ثبت نشده است.');
              return SizedBox(
                height: 360,
                child: ListView.separated(
                  itemCount: transactions.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final transaction = transactions[index];
                    final positive = transaction.points >= 0;
                    final typeLabel = switch (transaction.type) {
                      'earned' => 'کسب امتیاز',
                      'redeemed' => 'مصرف امتیاز',
                      'adjusted' => 'اصلاح دستی',
                      _ => 'سایر',
                    };
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(typeLabel),
                      subtitle: Text([
                        transaction.description,
                        if (transaction.orderId != null) 'سفارش: ${transaction.orderId}',
                        if (transaction.createdAt != null) _formatDateTime(transaction.createdAt!),
                      ].where((part) => part.isNotEmpty).join('\n')),
                      trailing: Text(
                        '${positive ? '+' : ''}${_number(transaction.points)}',
                        style: TextStyle(color: positive ? Colors.green : Colors.red, fontWeight: FontWeight.bold),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('بستن'))],
      ),
    );
  }

  Future<void> _adjustPoints(LoyaltyWalletModel wallet) async {
    final pointsController = TextEditingController();
    final descriptionController = TextEditingController();
    var isAdding = true;
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<({int points, String description})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('اصلاح امتیاز مشتری'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('افزایش'), icon: Icon(Icons.add)),
                      ButtonSegment(value: false, label: Text('کاهش'), icon: Icon(Icons.remove)),
                    ],
                    selected: {isAdding},
                    onSelectionChanged: (value) => setDialogState(() => isAdding = value.first),
                  ),
                  const SizedBox(height: AppSizes.md),
                  TextFormField(
                    controller: pointsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'تعداد امتیاز', border: OutlineInputBorder()),
                    validator: (value) {
                      final parsed = int.tryParse(value?.trim() ?? '');
                      if (parsed == null || parsed <= 0) return 'عدد صحیح بزرگ‌تر از صفر وارد کنید.';
                      if (!isAdding && parsed > wallet.totalPoints) return 'میزان کاهش از موجودی فعلی بیشتر است.';
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSizes.md),
                  TextFormField(
                    controller: descriptionController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'دلیل اصلاح', border: OutlineInputBorder()),
                    validator: (value) => (value?.trim().isNotEmpty ?? false) ? null : 'ثبت دلیل الزامی است.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                final amount = int.parse(pointsController.text.trim()) * (isAdding ? 1 : -1);
                Navigator.pop(dialogContext, (points: amount, description: descriptionController.text.trim()));
              },
              child: const Text('ثبت اصلاح'),
            ),
          ],
        ),
      ),
    );
    pointsController.dispose();
    descriptionController.dispose();
    if (result == null || !mounted) return;

    try {
      await _repository.adjustPoints(userId: wallet.userId, pointsDelta: result.points, description: result.description);
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('امتیاز و سابقه تراکنش به‌صورت اتمیک ثبت شد.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppErrorMessage.forDisplay(error.toString(), fallback: 'اصلاح امتیاز مشتری ناموفق بود. دوباره تلاش کنید.'))));
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(AppSizes.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text('باشگاه مشتریان و امتیازها', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold))),
              IconButton(tooltip: 'به‌روزرسانی', onPressed: _reload, icon: const Icon(Icons.refresh)),
            ]),
            const SizedBox(height: AppSizes.md),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'جست‌وجوی مشتری یا شماره تماس',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(onPressed: () { _searchController.clear(); _reload(); }, icon: const Icon(Icons.clear)),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _reload(),
            ),
            const SizedBox(height: AppSizes.md),
            Expanded(
              child: FutureBuilder<List<LoyaltyWalletModel>>(
                future: _walletsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  if (snapshot.hasError) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(AppErrorMessage.from(snapshot.error!, fallback: 'دریافت کیف امتیاز ناموفق بود. دوباره تلاش کنید.'), textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton(onPressed: _reload, child: const Text('تلاش مجدد'))]));
                  final wallets = snapshot.data ?? const <LoyaltyWalletModel>[];
                  if (wallets.isEmpty) return const Center(child: Text('کیف امتیازی برای نمایش وجود ندارد.'));
                  return ListView.separated(
                    itemCount: wallets.length,
                    separatorBuilder: (_, _) => const SizedBox(height: AppSizes.sm),
                    itemBuilder: (context, index) {
                      final wallet = wallets[index];
                      return Card(child: Padding(padding: const EdgeInsets.all(AppSizes.md), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const CircleAvatar(child: Icon(Icons.loyalty_outlined)), const SizedBox(width: AppSizes.md),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(wallet.customerName.isEmpty ? 'مشتری بدون نام' : wallet.customerName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            Text(wallet.customerPhone.isEmpty ? 'شماره تماس ثبت نشده' : wallet.customerPhone),
                            Text('شناسه مشتری: ${wallet.userId}', style: Theme.of(context).textTheme.bodySmall),
                          ])),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(_number(wallet.totalPoints), style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)), const Text('امتیاز')]),
                        ]),
                        const SizedBox(height: AppSizes.sm),
                        Wrap(spacing: AppSizes.sm, runSpacing: AppSizes.sm, children: [
                          OutlinedButton.icon(onPressed: () => _showTransactions(wallet), icon: const Icon(Icons.history), label: const Text('گردش امتیاز')),
                          FilledButton.tonalIcon(onPressed: () => _adjustPoints(wallet), icon: const Icon(Icons.tune), label: const Text('اصلاح امتیاز')),
                        ]),
                      ])));
                    },
                  );
                },
              ),
            ),
          ],
        ),
      );
}
