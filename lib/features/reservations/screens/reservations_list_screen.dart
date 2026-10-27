import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/utils/app_error_message.dart';
import '../../../models/reservation_model.dart';
import '../../../models/table_model.dart';
import '../../../models/user_model.dart';
import '../../../providers/reservations_provider.dart';
import '../../../providers/tables_provider.dart';
import '../../../repositories/customers_repository.dart';

class ReservationsListScreen extends StatefulWidget {
  const ReservationsListScreen({super.key});
  @override
  State<ReservationsListScreen> createState() => _ReservationsListScreenState();
}

class _ReservationsListScreenState extends State<ReservationsListScreen> {
  final _search = TextEditingController();
  static const _statuses = ['all', 'pending', 'confirmed', 'completed', 'cancelled'];
  final _dateFormat = DateFormat('yyyy/MM/dd');

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (!mounted) return;
    final reservationsProvider = context.read<ReservationsProvider>();
    final tablesProvider = context.read<TablesProvider>();
    await reservationsProvider.fetchReservations();
    if (!mounted) return;
    await tablesProvider.fetchTables();
  }); }
  @override
  void dispose() { _search.dispose(); super.dispose(); }

  String _statusLabel(String status) => switch (status) {
    'pending' => 'در انتظار',
    'confirmed' => 'تأییدشده',
    'completed' => 'تکمیل‌شده',
    'cancelled' => 'لغوشده',
    _ => 'نامشخص',
  };

  String _persianDigits(Object? value) {
    const latin = '0123456789';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    var result = value?.toString() ?? '';
    for (var i = 0; i < latin.length; i++) {
      result = result.replaceAll(latin[i], persian[i]);
    }
    return result;
  }

  String _formatDate(DateTime value) =>
      _persianDigits(_dateFormat.format(value));
  Color _statusColor(String status) => switch (status) {'pending' => Colors.orange, 'confirmed' => Colors.blue, 'completed' => Colors.green, 'cancelled' => Colors.red, _ => Colors.grey};

  Future<void> _showReservationForm([ReservationModel? current]) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final customersRepository = context.read<CustomersRepository>();
    final tablesProvider = context.read<TablesProvider>();
    final reservationsProvider = context.read<ReservationsProvider>();
    List<UserModel> customers;
    try {
      customers = await customersRepository.getCustomers(page: 1, pageSize: 100);
      if (!mounted) return;
      await tablesProvider.fetchTables();
    } catch (e) {
      if (mounted) scaffoldMessenger.showSnackBar(SnackBar(content: Text(AppErrorMessage.from(e, fallback: 'دریافت فهرست مشتریان یا میزها ناموفق بود. اتصال و سطح دسترسی را بررسی کنید.'))));
      return;
    }
    if (!mounted) return;
    final tables = context.read<TablesProvider>().tables.where((t) => t.isActive).toList();
    if (customers.isEmpty) { scaffoldMessenger.showSnackBar(const SnackBar(content: Text('برای ثبت رزرو، ابتدا باید مشتری ثبت شده باشد.'))); return; }
    if (tables.isEmpty) { scaffoldMessenger.showSnackBar(const SnackBar(content: Text('هیچ میز فعالی در پایگاه داده ثبت نشده است.'))); return; }

    final guestController = TextEditingController(text: (current?.partySize ?? 2).toString());
    final noteController = TextEditingController(text: current?.note ?? '');
    String? customerId = current?.userId ?? customers.first.id;
    String? tableId = current?.tableId ?? tables.first.id;
    DateTime date = current?.date ?? DateTime.now();
    final currentTimeParts = (current?.time ?? '19:00').split(':');
    TimeOfDay time = TimeOfDay(hour: int.tryParse(currentTimeParts.first) ?? 19, minute: currentTimeParts.length > 1 ? (int.tryParse(currentTimeParts[1]) ?? 0) : 0);

    final result = await showDialog<bool>(context: context, barrierDismissible: false, builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, setDialogState) => AlertDialog(
      title: Text(current == null ? 'ثبت رزرو جدید' : 'ویرایش رزرو'),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(initialValue: customerId, isExpanded: true, decoration: const InputDecoration(labelText: 'مشتری', border: OutlineInputBorder()), items: customers.map((c) => DropdownMenuItem(value: c.id, child: Text('${c.fullName} • ${c.phone ?? 'بدون تلفن'}', overflow: TextOverflow.ellipsis))).toList(), onChanged: current == null ? (value) => setDialogState(() => customerId = value) : null),
        const SizedBox(height: 12), DropdownButtonFormField<String>(initialValue: tableId, isExpanded: true, decoration: const InputDecoration(labelText: 'میز', border: OutlineInputBorder()), items: tables.map((t) => DropdownMenuItem(value: t.id, child: Text('میز ${_persianDigits(t.tableNumber)} • ظرفیت ${_persianDigits(t.capacity)}${t.status == TableStatus.occupied ? ' • اشغال' : ''}'))).toList(), onChanged: (value) => setDialogState(() => tableId = value)),
        const SizedBox(height: 12), TextFormField(controller: guestController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'تعداد نفرات', border: OutlineInputBorder())),
        const SizedBox(height: 12), Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () async { final selected = await showDatePicker(context: dialogContext, initialDate: date, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 730))); if (selected != null) setDialogState(() => date = selected); }, icon: const Icon(Icons.calendar_today), label: Text(_formatDate(date)))), const SizedBox(width: 8), Expanded(child: OutlinedButton.icon(onPressed: () async { final selected = await showTimePicker(context: dialogContext, initialTime: time); if (selected != null) setDialogState(() => time = selected); }, icon: const Icon(Icons.schedule), label: Text(time.format(dialogContext))))]),
        const SizedBox(height: 12), TextField(controller: noteController, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'یادداشت (اختیاری)', border: OutlineInputBorder()))
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')), FilledButton(onPressed: () async { final guests = int.tryParse(guestController.text.trim()); if (customerId == null || tableId == null || guests == null || guests < 1) { ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('مشتری، میز و تعداد نفرات را صحیح انتخاب کنید.'))); return; }
        TableModel? selectedTable;
        for (final candidate in tables) { if (candidate.id == tableId) { selectedTable = candidate; break; } }
        if (selectedTable == null || guests > selectedTable.capacity) {
          ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('تعداد مهمانان از ظرفیت میز بیشتر است یا میز معتبر نیست.')));
          return;
        }
        final provider = reservationsProvider;
        final timeValue = '${time.hour.toString().padLeft(2,'0')}:${time.minute.toString().padLeft(2,'0')}:00';
        final ok = current == null
          ? await provider.createReservation(userId: customerId!, tableId: tableId!, guestCount: guests, date: date, time: timeValue, note: noteController.text)
          : await provider.updateReservationDetails(id: current.id, tableId: tableId!, guestCount: guests, date: date, time: timeValue, note: noteController.text);
        if (!dialogContext.mounted) return;
        if (ok) {
          Navigator.pop(dialogContext, true);
        } else {
          ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(provider.error ?? 'ذخیره رزرو ناموفق بود.')));
        }
      }, child: Text(current == null ? 'ثبت رزرو' : 'ذخیره تغییرات'))]
    )));
    guestController.dispose(); noteController.dispose();
    if (result == true && mounted) { await reservationsProvider.fetchReservations(); if (!mounted) return; await tablesProvider.fetchTables(); if (!mounted) return; scaffoldMessenger.showSnackBar(const SnackBar(content: Text('رزرو ذخیره شد.'))); }
  }

  Future<void> _changeStatus(ReservationModel reservation, String status) async {
    final provider = context.read<ReservationsProvider>();
    final tablesProvider = context.read<TablesProvider>();
    final ok = await provider.updateReservationStatus(reservation.id, status);
    if (!mounted) return;
    if (!ok) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(provider.error ?? 'تغییر وضعیت رزرو ناموفق بود.')));
    await tablesProvider.fetchTables();
  }

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Expanded(child: Text('مدیریت رزرو میزها', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold))), FilledButton.icon(onPressed: () => _showReservationForm(), icon: const Icon(Icons.add), label: const Text('رزرو جدید'))]),
    const SizedBox(height: 14), TextField(controller: _search, decoration: InputDecoration(labelText: 'جست‌وجوی مشتری، تلفن یا شماره میز', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(onPressed: () { _search.clear(); context.read<ReservationsProvider>().setSearchQuery(''); }, icon: const Icon(Icons.clear)), border: const OutlineInputBorder()), onSubmitted: (v) => context.read<ReservationsProvider>().setSearchQuery(v)),
    const SizedBox(height: 12),
    SizedBox(
      height: 42,
      child: Consumer<ReservationsProvider>(
        builder: (context, provider, _) => ListView(
          scrollDirection: Axis.horizontal,
          children: _statuses.map((status) => Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: ChoiceChip(
              label: Text(status == 'all' ? 'همه' : _statusLabel(status)),
              selected: provider.statusFilter == status,
              onSelected: (_) => provider.setStatusFilter(status),
            ),
          )).toList(),
        ),
      ),
    ),
    const SizedBox(height: 12), Expanded(child: Consumer<ReservationsProvider>(builder: (context, provider, _) {
      if (provider.isLoading && provider.reservations.isEmpty) return const Center(child: CircularProgressIndicator());
      if (provider.error != null && provider.reservations.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(provider.error!, textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton(onPressed: provider.fetchReservations, child: const Text('تلاش مجدد'))]));
      if (provider.reservations.isEmpty) return const Center(child: Text('رزروی برای نمایش وجود ندارد.'));
      return Column(children: [Expanded(child: ListView.separated(itemCount: provider.reservations.length, separatorBuilder: (_, _) => const SizedBox(height: 8), itemBuilder: (context, index) {
        final reservation = provider.reservations[index];
        return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(reservation.customerName.isEmpty ? 'مشتری بدون نام' : reservation.customerName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: _statusColor(reservation.status.name).withValues(alpha: .12), borderRadius: BorderRadius.circular(20)), child: Text(_statusLabel(reservation.status.name), style: TextStyle(color: _statusColor(reservation.status.name))))]),
          const SizedBox(height: 8), Text('تلفن: ${reservation.customerPhone.isEmpty ? 'ثبت نشده' : reservation.customerPhone}'), Text('تاریخ: ${_formatDate(reservation.date)} • ساعت: ${_persianDigits(reservation.time)} • نفرات: ${_persianDigits(reservation.partySize)}'), Text('میز: ${reservation.tableNumber.isEmpty ? 'نامشخص' : reservation.tableNumber}'), if (reservation.note?.isNotEmpty == true) Text('یادداشت: ${reservation.note}'),
          const SizedBox(height: 8), Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 4, children: [OutlinedButton.icon(onPressed: () => _showReservationForm(reservation), icon: const Icon(Icons.edit_outlined), label: const Text('ویرایش زمان/میز')), PopupMenuButton<String>(tooltip: 'تغییر وضعیت', onSelected: (status) => _changeStatus(reservation, status), itemBuilder: (_) => const [PopupMenuItem(value: 'pending', child: Text('در انتظار')), PopupMenuItem(value: 'confirmed', child: Text('تأیید')), PopupMenuItem(value: 'completed', child: Text('تکمیل')), PopupMenuItem(value: 'cancelled', child: Text('لغو'))], child: const Chip(avatar: Icon(Icons.sync_alt, size: 18), label: Text('وضعیت')))])
        ])));
      })), Row(mainAxisAlignment: MainAxisAlignment.center, children: [IconButton(onPressed: provider.currentPage > 1 ? () => provider.changePage(provider.currentPage - 1) : null, icon: const Icon(Icons.chevron_right)), Text('صفحه ${_persianDigits(provider.currentPage)}'), IconButton(onPressed: provider.reservations.length == 15 ? () => provider.changePage(provider.currentPage + 1) : null, icon: const Icon(Icons.chevron_left))])]);
    }))
  ]));
}
