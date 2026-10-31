import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:provider/provider.dart';
import '../../../core/utils/app_error_message.dart';
import '../../../models/reservation_model.dart';
import '../../../models/table_model.dart';
import '../../../models/user_model.dart';
import '../../../providers/reservations_provider.dart';
import '../../../providers/tables_provider.dart';
import '../../../repositories/customers_repository.dart';
import '../widgets/reservations_calendar.dart';

class ReservationsListScreen extends StatefulWidget {
  const ReservationsListScreen({super.key});
  @override
  State<ReservationsListScreen> createState() => _ReservationsListScreenState();
}

class _ReservationsListScreenState extends State<ReservationsListScreen> {
  final _search = TextEditingController();
  static const _statuses = ['all', 'pending', 'confirmed', 'completed', 'cancelled'];
  Jalali _visibleMonth = Jalali.now();
  Jalali _selectedDate = Jalali.now();
  bool _showWholeMonth = false;

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (!mounted) return;
    final reservationsProvider = context.read<ReservationsProvider>();
    final tablesProvider = context.read<TablesProvider>();
    await reservationsProvider.setDateRange(from: _monthStart(_visibleMonth), to: _monthEnd(_visibleMonth));
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

  DateTime _monthStart(Jalali month) => Jalali(month.year, month.month, 1).toGregorian().toDateTime();
  DateTime _monthEnd(Jalali month) => Jalali(month.year, month.month, month.monthLength).toGregorian().toDateTime();

  String _formatDate(DateTime value) {
    final date = Jalali.fromDateTime(value).formatter;
    return _persianDigits('${date.yyyy}/${date.mm}/${date.dd}');
  }

  String _dateKey(DateTime value) {
    final date = value.toIso8601String();
    return date.length >= 10 ? date.substring(0, 10) : date;
  }

  Future<void> _changeMonth(int amount) async {
    final next = Jalali(_visibleMonth.year, _visibleMonth.month, 1).addMonths(amount);
    setState(() {
      _visibleMonth = next;
      _selectedDate = next;
      _showWholeMonth = false;
    });
    await context.read<ReservationsProvider>().setDateRange(from: _monthStart(next), to: _monthEnd(next));
  }

  Future<void> _selectDate(Jalali date) async {
    final monthChanged = date.year != _visibleMonth.year || date.month != _visibleMonth.month;
    setState(() {
      _selectedDate = date;
      _visibleMonth = Jalali(date.year, date.month, 1);
      _showWholeMonth = false;
    });
    if (monthChanged) {
      await context.read<ReservationsProvider>().setDateRange(from: _monthStart(_visibleMonth), to: _monthEnd(_visibleMonth));
    }
  }

  Future<void> _goToToday() async {
    final today = Jalali.now();
    setState(() {
      _visibleMonth = Jalali(today.year, today.month, 1);
      _selectedDate = today;
      _showWholeMonth = false;
    });
    await context.read<ReservationsProvider>().setDateRange(from: _monthStart(_visibleMonth), to: _monthEnd(_visibleMonth));
  }
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
    DateTime date = current?.date ?? _selectedDate.toGregorian().toDateTime();
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Consumer<ReservationsProvider>(
        builder: (context, provider, _) {
          final reservations = provider.reservations;
          final statusesByDay = <String, List<ReservationStatus>>{};
          for (final reservation in reservations) {
            final key = _dateKey(reservation.date);
            statusesByDay.putIfAbsent(key, () => []).add(reservation.status);
          }
          final visibleReservations = _showWholeMonth
              ? reservations
              : reservations.where((reservation) {
                  final date = Jalali.fromDateTime(reservation.date);
                  return date.year == _selectedDate.year &&
                      date.month == _selectedDate.month &&
                      date.day == _selectedDate.day;
                }).toList();
          final pendingCount = reservations.where((r) => r.status == ReservationStatus.pending).length;
          final confirmedCount = reservations.where((r) => r.status == ReservationStatus.confirmed).length;
          final completedCount = reservations.where((r) => r.status == ReservationStatus.completed).length;
          final cancelledCount = reservations.where((r) => r.status == ReservationStatus.cancelled).length;

          return RefreshIndicator(
            onRefresh: provider.fetchReservations,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('تقویم رزروها', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text('برنامه‌ریزی و مدیریت رزرو میزها', style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _showReservationForm(),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('رزرو جدید'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _summaryCard(context, 'کل رزروهای ماه', reservations.length, Icons.event_available_rounded, scheme.primary),
                      _summaryCard(context, 'در انتظار', pendingCount, Icons.hourglass_top_rounded, const Color(0xFFF59E0B)),
                      _summaryCard(context, 'تأییدشده', confirmedCount, Icons.check_circle_outline_rounded, const Color(0xFF3B82F6)),
                      _summaryCard(context, 'تکمیل‌شده', completedCount, Icons.task_alt_rounded, const Color(0xFF16A34A)),
                      _summaryCard(context, 'لغوشده', cancelledCount, Icons.event_busy_rounded, scheme.error),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ReservationsCalendar(
                    visibleMonth: _visibleMonth,
                    selectedDate: _selectedDate,
                    statusesByDay: statusesByDay,
                    onDateSelected: _selectDate,
                    onPreviousMonth: () => _changeMonth(-1),
                    onNextMonth: () => _changeMonth(1),
                    onToday: _goToToday,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      Text(
                        _showWholeMonth ? 'رزروهای ماه ${_persianDigits('${_visibleMonth.year}/${_visibleMonth.month.toString().padLeft(2, '0')}')}' : 'رزروهای ${_formatDate(_selectedDate.toGregorian().toDateTime())}',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('روز انتخاب‌شده'), icon: Icon(Icons.today_rounded)),
                          ButtonSegment(value: true, label: Text('کل ماه'), icon: Icon(Icons.calendar_view_month_rounded)),
                        ],
                        selected: {_showWholeMonth},
                        onSelectionChanged: (selection) => setState(() => _showWholeMonth = selection.first),
                        showSelectedIcon: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    onSubmitted: provider.setSearchQuery,
                    decoration: InputDecoration(
                      hintText: 'جست‌وجوی نام مشتری، تلفن یا شماره میز',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        tooltip: 'پاک کردن جست‌وجو',
                        onPressed: () {
                          _search.clear();
                          provider.setSearchQuery('');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _statuses.map((status) => Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ChoiceChip(
                          label: Text(status == 'all' ? 'همه وضعیت‌ها' : _statusLabel(status)),
                          selected: provider.statusFilter == status,
                          onSelected: (_) => provider.setStatusFilter(status),
                          showCheckmark: false,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      )).toList(),
                    ),
                  ),
                  if (provider.isLoading) const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                  const SizedBox(height: 10),
                  if (provider.error != null && reservations.isEmpty)
                    _emptyState(context, provider.error!, actionLabel: 'تلاش مجدد', onAction: provider.fetchReservations)
                  else if (visibleReservations.isEmpty)
                    _emptyState(
                      context,
                      _showWholeMonth ? 'در این ماه رزروی با فیلترهای انتخاب‌شده وجود ندارد.' : 'برای این روز رزروی با فیلترهای انتخاب‌شده ثبت نشده است.',
                      actionLabel: 'ثبت رزرو',
                      onAction: () => _showReservationForm(),
                    )
                  else
                    ...visibleReservations.map((reservation) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _reservationCard(context, reservation),
                    )),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _summaryCard(BuildContext context, String label, int count, IconData icon, Color color) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 145),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: .65)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, size: 19, color: color),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_persianDigits(count), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ]),
    );
  }

  Widget _reservationCard(BuildContext context, ReservationModel reservation) {
    final theme = Theme.of(context);
    final color = _statusColor(reservation.status.name);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: .65)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: .09), borderRadius: BorderRadius.circular(13)),
              child: Icon(Icons.person_outline_rounded, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(reservation.customerName.isEmpty ? 'مشتری بدون نام' : reservation.customerName,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              Text(reservation.customerPhone.isEmpty ? 'شماره تماس ثبت نشده' : reservation.customerPhone,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(30)),
              child: Text(_statusLabel(reservation.status.name), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 16, runSpacing: 10, children: [
            _detailItem(context, Icons.calendar_today_rounded, _formatDate(reservation.date)),
            _detailItem(context, Icons.schedule_rounded, _persianDigits(reservation.time)),
            _detailItem(context, Icons.groups_2_outlined, '${_persianDigits(reservation.partySize)} نفر'),
            _detailItem(context, Icons.table_restaurant_outlined, 'میز ${_persianDigits(reservation.tableNumber)}'),
          ]),
          if (reservation.note?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text('یادداشت: ${reservation.note}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _showReservationForm(reservation),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('ویرایش'),
              ),
              PopupMenuButton<String>(
                tooltip: 'تغییر وضعیت رزرو',
                onSelected: (status) => _changeStatus(reservation, status),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'pending', child: Text('در انتظار')),
                  PopupMenuItem(value: 'confirmed', child: Text('تأیید رزرو')),
                  PopupMenuItem(value: 'completed', child: Text('تکمیل رزرو')),
                  PopupMenuItem(value: 'cancelled', child: Text('لغو رزرو')),
                ],
                child: const Chip(avatar: Icon(Icons.swap_horiz_rounded, size: 18), label: Text('تغییر وضعیت')),
              ),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _detailItem(BuildContext context, IconData icon, String value) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
      const SizedBox(width: 6),
      Text(value, style: Theme.of(context).textTheme.bodySmall),
    ],
  );

  Widget _emptyState(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 34),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .65)),
      ),
      child: Column(children: [
        Icon(Icons.event_note_rounded, size: 38, color: scheme.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 14),
          OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ]),
    );
  }
}
