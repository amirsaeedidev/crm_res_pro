import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';
import '../../../models/reservation_model.dart';

class ReservationsCalendar extends StatelessWidget {
  final Jalali visibleMonth;
  final Jalali selectedDate;
  final Map<String, List<ReservationStatus>> statusesByDay;
  final ValueChanged<Jalali> onDateSelected;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onToday;

  const ReservationsCalendar({
    super.key, required this.visibleMonth, required this.selectedDate,
    required this.statusesByDay, required this.onDateSelected,
    required this.onPreviousMonth, required this.onNextMonth, required this.onToday,
  });

  static const _weekdays = ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج'];

  String _dateKey(Jalali date) {
    final g = date.toGregorian().toDateTime();
    return '${g.year.toString().padLeft(4, '0')}-${g.month.toString().padLeft(2, '0')}-${g.day.toString().padLeft(2, '0')}';
  }

  String _digits(String value) {
    const latin = '0123456789', persian = '۰۱۲۳۴۵۶۷۸۹';
    var result = value;
    for (var i = 0; i < latin.length; i++) { result = result.replaceAll(latin[i], persian[i]); }
    return result;
  }

  Color _statusColor(ReservationStatus status, ColorScheme scheme) => switch (status) {
    ReservationStatus.pending => const Color(0xFFF59E0B),
    ReservationStatus.confirmed => const Color(0xFF3B82F6),
    ReservationStatus.completed => const Color(0xFF16A34A),
    ReservationStatus.cancelled => scheme.error,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final firstDay = Jalali(visibleMonth.year, visibleMonth.month, 1);
    final gridStart = firstDay.addDays(-(firstDay.weekDay - 1));
    final title = '${visibleMonth.formatter.mN} ${_digits(visibleMonth.year.toString())}';

    return Card(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .65)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .10), borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.calendar_month_rounded, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              Text('تقویم شمسی رزروها', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ])),
            IconButton(tooltip: 'ماه قبل', onPressed: onPreviousMonth, icon: const Icon(Icons.chevron_right_rounded)),
            IconButton(tooltip: 'ماه بعد', onPressed: onNextMonth, icon: const Icon(Icons.chevron_left_rounded)),
            const SizedBox(width: 4),
            OutlinedButton(onPressed: onToday, child: const Text('امروز')),
          ]),
          const SizedBox(height: 18),
          Row(children: _weekdays.map((day) => Expanded(child: Center(child: Text(
            day, style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700),
          )))).toList()),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: 42,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7, mainAxisSpacing: 5, crossAxisSpacing: 5, childAspectRatio: 1.12,
            ),
            itemBuilder: (context, index) {
              final date = gridStart.addDays(index);
              final inMonth = date.month == visibleMonth.month && date.year == visibleMonth.year;
              final selected = date.year == selectedDate.year && date.month == selectedDate.month && date.day == selectedDate.day;
              final statuses = statusesByDay[_dateKey(date)] ?? const [];
              final count = statuses.length;
              final foreground = selected ? scheme.onPrimary : inMonth ? scheme.onSurface : scheme.onSurface.withValues(alpha: .30);
              return Material(
                color: selected ? scheme.primary : count > 0 ? scheme.primary.withValues(alpha: .055) : Colors.transparent,
                borderRadius: BorderRadius.circular(13),
                child: InkWell(
                  borderRadius: BorderRadius.circular(13),
                  onTap: () => onDateSelected(date),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(_digits(date.day.toString()), style: theme.textTheme.bodyMedium?.copyWith(
                        color: foreground, fontWeight: selected || count > 0 ? FontWeight.w800 : FontWeight.w500,
                      )),
                      const SizedBox(height: 3),
                      if (count > 0)
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          ...statuses.take(3).map((status) => Container(
                            width: 5, height: 5, margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(color: selected ? scheme.onPrimary : _statusColor(status, scheme), shape: BoxShape.circle),
                          )),
                          if (count > 3) Text('+', style: TextStyle(color: foreground, fontSize: 8, height: 1)),
                        ])
                      else
                        const SizedBox(height: 5),
                    ]),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 14, runSpacing: 8, children: [
            _Legend(color: const Color(0xFFF59E0B), label: 'در انتظار'),
            _Legend(color: const Color(0xFF3B82F6), label: 'تأییدشده'),
            _Legend(color: const Color(0xFF16A34A), label: 'تکمیل‌شده'),
            _Legend(color: scheme.error, label: 'لغوشده'),
          ]),
        ]),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 6),
    Text(label, style: Theme.of(context).textTheme.labelSmall),
  ]);
}
