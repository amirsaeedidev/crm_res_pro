enum ReservationStatus { pending, confirmed, delayed, arrived, completed, cancelled, noShow }

extension ReservationStatusX on ReservationStatus {
  String get name => switch (this) {
    ReservationStatus.pending => 'pending',
    ReservationStatus.confirmed => 'confirmed',
    ReservationStatus.delayed => 'delayed',
    ReservationStatus.arrived => 'arrived',
    ReservationStatus.completed => 'completed',
    ReservationStatus.cancelled => 'cancelled',
    ReservationStatus.noShow => 'no_show',
  };
  static ReservationStatus fromString(String? value) => switch (value?.toLowerCase()) {
    'confirmed' => ReservationStatus.confirmed,
    'delayed' => ReservationStatus.delayed,
    'arrived' => ReservationStatus.arrived,
    'completed' || 'seated' => ReservationStatus.completed,
    'cancelled' || 'canceled' => ReservationStatus.cancelled,
    'no_show' => ReservationStatus.noShow,
    _ => ReservationStatus.pending,
  };
}

class ReservationModel {
  final String id;
  final String? userId, tableId;
  final String customerName, customerPhone, time, tableNumber;
  final DateTime date;
  final int partySize, durationMinutes;
  final String? note, delayNote, cancellationReason, orderId;
  final ReservationStatus status;
  final DateTime? createdAt, arrivedAt, delayedAt, cancelledAt, noShowAt;
  final int? delayMinutes;

  const ReservationModel({
    required this.id, this.userId, this.tableId, required this.customerName,
    required this.customerPhone, required this.date, required this.time,
    required this.partySize, required this.tableNumber, this.note,
    this.status = ReservationStatus.pending, this.createdAt, this.durationMinutes = 90,
    this.arrivedAt, this.delayedAt, this.delayMinutes, this.delayNote,
    this.cancelledAt, this.cancellationReason, this.noShowAt, this.orderId,
  });

  factory ReservationModel.fromJson(Map<String, dynamic> json) {
    final created = DateTime.tryParse((json['created_at'] ?? '').toString());
    final dateString = (json['date'] ?? json['reservation_date'] ?? '').toString();
    final timeString = (json['time'] ?? json['reservation_time'] ?? '').toString();
    DateTime? dateValue(String key) => DateTime.tryParse((json[key] ?? '').toString());
    return ReservationModel(
      id: json['id'].toString(), userId: json['user_id']?.toString(), tableId: json['table_id']?.toString(),
      customerName: (json['customer_name'] ?? '').toString(), customerPhone: (json['customer_phone'] ?? '').toString(),
      date: DateTime.tryParse(dateString) ?? created ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      time: timeString.isEmpty ? (created == null ? '—' : '${created.hour.toString().padLeft(2,'0')}:${created.minute.toString().padLeft(2,'0')}') : timeString.substring(0, timeString.length >= 5 ? 5 : timeString.length),
      partySize: (json['party_size'] as num? ?? json['guest_count'] as num? ?? 1).toInt(),
      tableNumber: (json['table_number'] ?? '').toString(), note: json['note'] as String?,
      status: ReservationStatusX.fromString(json['status'] as String?), createdAt: created,
      durationMinutes: (json['duration_minutes'] as num? ?? 90).toInt(),
      arrivedAt: dateValue('arrived_at'), delayedAt: dateValue('delayed_at'),
      delayMinutes: (json['delay_minutes'] as num?)?.toInt(), delayNote: json['delay_note'] as String?,
      cancelledAt: dateValue('cancelled_at'), cancellationReason: json['cancellation_reason'] as String?,
      noShowAt: dateValue('no_show_at'), orderId: json['order_id']?.toString(),
    );
  }
  @override
  bool operator ==(Object other) => other is ReservationModel && other.id == id;
  @override
  int get hashCode => id.hashCode;
}
