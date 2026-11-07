import 'dart:async';

import 'package:flutter/material.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';
import 'package:provider/provider.dart';
import 'package:hugeicons/hugeicons.dart';
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
  static const _statuses = ['all', 'pending', 'confirmed', 'delayed', 'arrived', 'completed', 'no_show', 'cancelled'];

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
    'delayed' => 'دارای تأخیر',
    'arrived' => 'مشتری حاضر شد',
    'completed' => 'تکمیل‌شده',
    'no_show' => 'عدم مراجعه',
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

  String _formatDate(DateTime value) {
    final jalali = Jalali.fromDateTime(value);
    final formatted =
        '${jalali.year}/${jalali.month.toString().padLeft(2, '0')}/${jalali.day.toString().padLeft(2, '0')}';
    return _persianDigits(formatted);
  }
  Color _statusColor(String status) => switch (status) {'pending' => Colors.orange, 'confirmed' => Colors.blue, 'delayed' => Colors.deepOrange, 'arrived' => Colors.teal, 'completed' => Colors.green, 'no_show' => Colors.deepPurple, 'cancelled' => Colors.red, _ => Colors.grey};

  Future<void> _showReservationForm([ReservationModel? current]) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final customersRepository = context.read<CustomersRepository>();
    final tablesProvider = context.read<TablesProvider>();
    final reservationsProvider = context.read<ReservationsProvider>();
    List<UserModel> customers;
    try {
      customers = await customersRepository.getCustomers(page: 1, pageSize: 8);
      if (current?.userId != null &&
          !customers.any((customer) => customer.id == current!.userId)) {
        final selected = await customersRepository.getCustomerById(current!.userId!);
        customers = [selected, ...customers];
      }
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
    final durationController = TextEditingController(text: (current?.durationMinutes ?? 90).toString());
    final noteController = TextEditingController(text: current?.note ?? '');
    final customerSearchController = TextEditingController();
    String? customerId = current?.userId;
    UserModel? selectedCustomer;
    for (final customer in customers) {
      if (customer.id == customerId) {
        selectedCustomer = customer;
        break;
      }
    }
    customerSearchController.text = selectedCustomer?.fullName ?? '';
    List<UserModel> customerSuggestions = List<UserModel>.of(customers.take(8));
    bool customerSearchLoading = false;
    Timer? customerLookupDebounce;
    int customerSearchRequest = 0;

    void searchCustomers(String value, StateSetter updateDialog, BuildContext searchContext) {
      customerLookupDebounce?.cancel();
      final requestId = ++customerSearchRequest;
      final query = value.trim();
      updateDialog(() {
        customerId = null;
        selectedCustomer = null;
        customerSearchLoading = query.isNotEmpty;
      });
      if (query.isEmpty) {
        updateDialog(() {
          customerSuggestions = List<UserModel>.of(customers.take(8));
          customerSearchLoading = false;
        });
        return;
      }
      customerLookupDebounce = Timer(const Duration(milliseconds: 350), () async {
        try {
          final matches = await customersRepository.getCustomers(
            page: 1,
            pageSize: 8,
            searchQuery: query,
          );
          if (!searchContext.mounted || requestId != customerSearchRequest) return;
          updateDialog(() {
            customerSuggestions = matches;
            customerSearchLoading = false;
          });
        } catch (_) {
          if (!searchContext.mounted || requestId != customerSearchRequest) return;
          updateDialog(() {
            customerSuggestions = [];
            customerSearchLoading = false;
          });
        }
      });
    }
    String? tableId = current?.tableId ?? tables.first.id;
    DateTime date = current?.date ?? DateTime.now();
    final currentTimeParts = (current?.time ?? '19:00').split(':');
    TimeOfDay time = TimeOfDay(hour: int.tryParse(currentTimeParts.first) ?? 19, minute: currentTimeParts.length > 1 ? (int.tryParse(currentTimeParts[1]) ?? 0) : 0);

    final result = await showDialog<bool>(context: context, barrierDismissible: false, builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, setDialogState) => AlertDialog(
      title: Text(current == null ? 'ثبت رزرو جدید' : 'ویرایش رزرو'),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: customerSearchController,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'جست‌وجوی مشتری با نام یا شماره تلفن',
            hintText: 'نام یا شماره موبایل را وارد کنید',
            prefixIcon: const HugeIcon(icon: HugeIcons.strokeRoundedUserGroup),
            suffixIcon: customerSearchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'پاک‌کردن جست‌وجو',
                    onPressed: () {
                      customerSearchController.clear();
                      searchCustomers('', setDialogState, dialogContext);
                    },
                    icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01),
                  ),
            border: const OutlineInputBorder(),
          ),
          onChanged: (value) => searchCustomers(value, setDialogState, dialogContext),
        ),
        const SizedBox(height: 8),
        if (selectedCustomer != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(dialogContext).colorScheme.primaryContainer.withValues(alpha: .35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(dialogContext).colorScheme.primary.withValues(alpha: .25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const HugeIcon(icon: HugeIcons.strokeRoundedUserCheck01, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(selectedCustomer!.fullName, style: const TextStyle(fontWeight: FontWeight.w700))),
                  TextButton(
                    onPressed: () {
                      customerSearchController.clear();
                      searchCustomers('', setDialogState, dialogContext);
                    },
                    child: const Text('تغییر'),
                  ),
                ]),
                Text('تلفن: ${selectedCustomer!.phone?.isNotEmpty == true ? selectedCustomer!.phone : 'ثبت نشده'}'),
                const SizedBox(height: 3),
                SelectableText(
                  'شناسه مشتری: ${selectedCustomer!.id}',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ],
            ),
          )
        else
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 190),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(dialogContext).dividerColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: customerSearchLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : customerSuggestions.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: Text('مشتری‌ای با این مشخصات پیدا نشد.'),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: customerSuggestions.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final customer = customerSuggestions[index];
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              child: Text(customer.fullName.isEmpty ? '؟' : customer.fullName.substring(0, 1)),
                            ),
                            title: Text(customer.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('تلفن: ${customer.phone?.isNotEmpty == true ? customer.phone : 'ثبت نشده'}'),
                                Text('شناسه: ${customer.id}', maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                            onTap: () {
                              customerLookupDebounce?.cancel();
                              customerSearchRequest++;
                              setDialogState(() {
                                selectedCustomer = customer;
                                customerId = customer.id;
                                customerSuggestions = [];
                                customerSearchLoading = false;
                                customerSearchController.text = customer.fullName;
                              });
                            },
                          );
                        },
                      ),
          ),
        const SizedBox(height: 12), DropdownButtonFormField<String>(initialValue: tableId, isExpanded: true, decoration: const InputDecoration(labelText: 'میز', border: OutlineInputBorder()), items: tables.map((t) => DropdownMenuItem(value: t.id, child: Text('میز ${_persianDigits(t.tableNumber)} • ظرفیت ${_persianDigits(t.capacity)}${t.status == TableStatus.occupied ? ' • اشغال' : ''}'))).toList(), onChanged: (value) => setDialogState(() => tableId = value)),
        const SizedBox(height: 12), TextFormField(controller: guestController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'تعداد نفرات', border: OutlineInputBorder())),
        const SizedBox(height: 12), TextFormField(controller: durationController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مدت رزرو (دقیقه؛ ۱۵ تا ۴۸۰)', border: OutlineInputBorder())),
        const SizedBox(height: 12), Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final selected = await showPersianDatePicker(
                context: dialogContext,
                initialDate: Jalali.fromDateTime(date),
                firstDate: Jalali.fromDateTime(now.subtract(const Duration(days: 365))),
                lastDate: Jalali.fromDateTime(now.add(const Duration(days: 730))),
                initialEntryMode: PersianDatePickerEntryMode.calendarOnly,
              );
              if (selected != null) setDialogState(() => date = selected.toDateTime());
            },
            icon: const HugeIcon(icon: HugeIcons.strokeRoundedCalendar01),
            label: Text(_formatDate(date)),
          )),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(
            onPressed: () async {
              final selected = await showTimePicker(
                context: dialogContext,
                initialTime: time,
                builder: (context, child) => Directionality(
                  textDirection: TextDirection.rtl,
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
                    child: child!,
                  ),
                ),
              );
              if (selected != null) setDialogState(() => time = selected);
            },
            icon: const HugeIcon(icon: HugeIcons.strokeRoundedClock01),
            label: Text(time.format(dialogContext)),
          )),
        ]),
        const SizedBox(height: 12), TextField(controller: noteController, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'یادداشت (اختیاری)', border: OutlineInputBorder()))
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')), FilledButton(onPressed: () async { final guests = int.tryParse(guestController.text.trim()); final duration = int.tryParse(durationController.text.trim()); if (customerId == null || tableId == null || guests == null || guests < 1 || duration == null || duration < 15 || duration > 480) { ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('مشتری را از فهرست پیشنهادها انتخاب کنید، سپس میز و تعداد نفرات را بررسی کنید.'))); return; }
        TableModel? selectedTable;
        for (final candidate in tables) { if (candidate.id == tableId) { selectedTable = candidate; break; } }
        if (selectedTable == null || guests > selectedTable.capacity) {
          ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('تعداد مهمانان از ظرفیت میز بیشتر است یا میز معتبر نیست.')));
          return;
        }
        final provider = reservationsProvider;
        final timeValue = '${time.hour.toString().padLeft(2,'0')}:${time.minute.toString().padLeft(2,'0')}:00';
        final ok = current == null
          ? await provider.createReservation(userId: customerId!, tableId: tableId!, guestCount: guests, date: date, time: timeValue, note: noteController.text, durationMinutes: duration)
          : await provider.updateReservationDetails(id: current.id, tableId: tableId!, guestCount: guests, date: date, time: timeValue, note: noteController.text);
        if (!dialogContext.mounted) return;
        if (ok) {
          Navigator.pop(dialogContext, true);
        } else {
          ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(provider.error ?? 'ذخیره رزرو ناموفق بود.')));
        }
      }, child: Text(current == null ? 'ثبت رزرو' : 'ذخیره تغییرات'))]
    )));
    customerLookupDebounce?.cancel();
    customerSearchController.dispose();
    guestController.dispose(); durationController.dispose(); noteController.dispose();
    if (result == true && mounted) { await reservationsProvider.fetchReservations(); if (!mounted) return; await tablesProvider.fetchTables(); if (!mounted) return; scaffoldMessenger.showSnackBar(const SnackBar(content: Text('رزرو ذخیره شد.'))); }
  }

  Future<void> _changeStatus(ReservationModel reservation, String status) async {
    final provider = context.read<ReservationsProvider>();
    final tablesProvider = context.read<TablesProvider>();
    String? reason;
    String? delayNote;
    int? delayMinutes;
    if (status == 'cancelled') {
      final controller = TextEditingController();
      reason = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('لغو رزرو'),
        content: TextField(controller: controller, autofocus: true, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'دلیل لغو (اجباری)')),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')), FilledButton(onPressed: () { if (controller.text.trim().isNotEmpty) Navigator.pop(ctx, controller.text.trim()); }, child: const Text('ثبت لغو'))],
      ));
      controller.dispose();
      if (reason == null) return;
    }
    if (status == 'delayed') {
      final minutesController = TextEditingController(text: '15');
      final noteController = TextEditingController();
      final result = await showDialog<(int, String?)>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('ثبت تأخیر مشتری'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: minutesController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مدت تأخیر به دقیقه')),
          const SizedBox(height: 8),
          TextField(controller: noteController, decoration: const InputDecoration(labelText: 'توضیح (اختیاری)')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')), FilledButton(onPressed: () { final value = int.tryParse(minutesController.text); if (value != null && value > 0 && value <= 480) Navigator.pop(ctx, (value, noteController.text.trim())); }, child: const Text('ثبت'))],
      ));
      minutesController.dispose(); noteController.dispose();
      if (result == null) return;
      delayMinutes = result.$1; delayNote = result.$2;
    }
    final ok = await provider.updateReservationStatus(reservation.id, status, reason: reason, delayMinutes: delayMinutes, delayNote: delayNote);
    if (!mounted) return;
    if (!ok) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(provider.error ?? 'تغییر وضعیت رزرو ناموفق بود.')));
    await tablesProvider.fetchTables();
  }

  Future<void> _convertToOrder(ReservationModel reservation) async {
    final provider = context.read<ReservationsProvider>();
    final orderId = await provider.convertReservationToOrder(reservation.id);
    if (!mounted) return;
    if (orderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(provider.error ?? 'تبدیل رزرو به سفارش ناموفق بود.')));
      return;
    }
    await context.read<TablesProvider>().fetchTables();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('سفارش حضوری با موفقیت ایجاد شد: ${orderId.substring(0, 8).toUpperCase()}')));
  }

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Expanded(child: Text('مدیریت رزرو میزها', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold))), FilledButton.icon(onPressed: () => _showReservationForm(), icon: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01), label: const Text('رزرو جدید'))]),
    const SizedBox(height: 14), TextField(controller: _search, decoration: InputDecoration(labelText: 'جست‌وجوی مشتری، تلفن یا شماره میز', prefixIcon: const HugeIcon(icon: HugeIcons.strokeRoundedSearch01), suffixIcon: IconButton(onPressed: () { _search.clear(); context.read<ReservationsProvider>().setSearchQuery(''); }, icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01)), border: const OutlineInputBorder()), onSubmitted: (v) => context.read<ReservationsProvider>().setSearchQuery(v)),
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
              selectedColor: status == 'all' ? Theme.of(context).colorScheme.primary : _statusColor(status),
              backgroundColor: status == 'all'
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : _statusColor(status).withValues(alpha: 0.10),
              labelStyle: TextStyle(
                color: provider.statusFilter == status
                    ? Colors.white
                    : status == 'all'
                        ? Theme.of(context).colorScheme.onSurface
                        : _statusColor(status),
                fontWeight: FontWeight.w600,
              ),
              side: BorderSide(
                color: status == 'all'
                    ? Theme.of(context).dividerColor
                    : _statusColor(status).withValues(alpha: 0.45),
              ),
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
          if (reservation.delayMinutes != null) Text('مدت تأخیر: ${_persianDigits(reservation.delayMinutes)} دقیقه'),
          if (reservation.delayNote?.isNotEmpty == true) Text('توضیح تأخیر: ${reservation.delayNote}'),
          if (reservation.cancellationReason?.isNotEmpty == true) Text('دلیل لغو: ${reservation.cancellationReason}'),
          Text('مدت رزرو: ${_persianDigits(reservation.durationMinutes)} دقیقه'),
          const SizedBox(height: 8), Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 4, children: [if (['pending', 'confirmed', 'delayed'].contains(reservation.status.name)) OutlinedButton.icon(onPressed: () => _showReservationForm(reservation), icon: const HugeIcon(icon: HugeIcons.strokeRoundedEdit02), label: const Text('ویرایش زمان/میز')), PopupMenuButton<String>(tooltip: 'تغییر وضعیت', onSelected: (status) => _changeStatus(reservation, status), itemBuilder: (_) => const [
            PopupMenuItem(value: 'pending', child: Text('در انتظار')),
            PopupMenuItem(value: 'confirmed', child: Text('تأیید')),
            PopupMenuItem(value: 'delayed', child: Text('ثبت تأخیر')),
            PopupMenuItem(value: 'arrived', child: Text('ثبت ورود مشتری')),
            PopupMenuItem(value: 'completed', child: Text('تکمیل رزرو')),
            PopupMenuItem(value: 'no_show', child: Text('عدم مراجعه')),
            PopupMenuItem(value: 'cancelled', child: Text('لغو رزرو')),
          ], child: const Chip(avatar: HugeIcon(icon: HugeIcons.strokeRoundedArrowLeftRight, size: 18), label: Text('وضعیت'))),
          if (reservation.orderId == null && !['cancelled','completed','no_show'].contains(reservation.status.name))
            OutlinedButton.icon(onPressed: () => _convertToOrder(reservation), icon: const Icon(Icons.restaurant, size: 18), label: const Text('تبدیل به سفارش'))
          else if (reservation.orderId != null)
            Chip(avatar: const Icon(Icons.receipt_long, size: 16), label: Text('سفارش ${reservation.orderId!.substring(0, 8)}'))
          ])
        ])));
      })), Row(mainAxisAlignment: MainAxisAlignment.center, children: [IconButton(onPressed: provider.currentPage > 1 ? () => provider.changePage(provider.currentPage - 1) : null, icon: const HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01)), Text('صفحه ${_persianDigits(provider.currentPage)}'), IconButton(onPressed: provider.reservations.length == 15 ? () => provider.changePage(provider.currentPage + 1) : null, icon: const HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01))])]);
    }))
  ]));
}
