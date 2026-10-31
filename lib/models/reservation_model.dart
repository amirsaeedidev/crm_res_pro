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
    'arrived' || 'seated' => ReservationStatus.arrived,
    'completed' => ReservationStatus.completed,
    'cancelled' => ReservationStatus.cancelled,
    'no_show' || 'noshow' => ReservationStatus.noShow,
    _ => ReservationStatus.pending,
  };
}

DateTime? _parseReservationDateTime(dynamic value) =>
    value == null ? null : DateTime.tryParse(value.toString());

class ReservationModel {
  final String id;
  final String? userId;
  final String? tableId;
  final String customerName;
  final String customerPhone;
  final DateTime date;
  final String time;
  final int partySize;
  final String tableNumber;
  final String? note;
  final ReservationStatus status;
  final DateTime? createdAt;
  final DateTime? arrivedAt;
  final DateTime? delayedAt;
  final int? delayMinutes;
  final String? delayNote;
  final DateTime? cancelledAt;
  final String? cancellationReason;
  final DateTime? noShowAt;

  const ReservationModel({
    required this.id, this.userId, this.tableId,
    required this.customerName, required this.customerPhone,
    required this.date, required this.time, required this.partySize,
    required this.tableNumber, this.note,
    this.status = ReservationStatus.pending, this.createdAt,
    this.arrivedAt, this.delayedAt, this.delayMinutes, this.delayNote,
    this.cancelledAt, this.cancellationReason, this.noShowAt,
  });

  factory ReservationModel.fromJson(Map<String, dynamic> json) {
    final created = _parseReservationDateTime(json['created_at']);
    final dateString = (json['date'] ?? json['reservation_date'] ?? '').toString();
    final timeString = (json['time'] ?? json['reservation_time'] ?? '').toString();
    return ReservationModel(
      id: json['id'].toString(),
      userId: json['user_id']?.toString(),
      tableId: json['table_id']?.toString(),
      customerName: (json['customer_name'] ?? '').toString(),
      customerPhone: (json['customer_phone'] ?? '').toString(),
      date: DateTime.tryParse(dateString) ?? created ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      time: timeString.isEmpty
          ? (created == null ? '—' : '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}')
          : timeString.substring(0, timeString.length >= 5 ? 5 : timeString.length),
      partySize: (json['party_size'] as num? ?? json['guest_count'] as num? ?? 1).toInt(),
      tableNumber: (json['table_number'] ?? '').toString(),
      note: json['note'] as String?,
      status: ReservationStatusX.fromString(json['status'] as String?),
      createdAt: created,
      arrivedAt: _parseReservationDateTime(json['arrived_at']),
      delayedAt: _parseReservationDateTime(json['delayed_at']),
      delayMinutes: (json['delay_minutes'] as num?)?.toInt(),
      delayNote: json['delay_note'] as String?,
      cancelledAt: _parseReservationDateTime(json['cancelled_at']),
      cancellationReason: json['cancellation_reason'] as String?,
      noShowAt: _parseReservationDateTime(json['no_show_at']),
    );
  }

  ReservationModel copyWith({
    String? id, String? userId, String? tableId, String? customerName,
    String? customerPhone, DateTime? date, String? time, int? partySize,
    String? tableNumber, String? note, ReservationStatus? status,
    DateTime? createdAt, DateTime? arrivedAt, DateTime? delayedAt,
    int? delayMinutes, String? delayNote, DateTime? cancelledAt,
    String? cancellationReason, DateTime? noShowAt,
  }) => ReservationModel(
    id: id ?? this.id, userId: userId ?? this.userId,
    tableId: tableId ?? this.tableId, customerName: customerName ?? this.customerName,
    customerPhone: customerPhone ?? this.customerPhone, date: date ?? this.date,
    time: time ?? this.time, partySize: partySize ?? this.partySize,
    tableNumber: tableNumber ?? this.tableNumber, note: note ?? this.note,
    status: status ?? this.status, createdAt: createdAt ?? this.createdAt,
    arrivedAt: arrivedAt ?? this.arrivedAt, delayedAt: delayedAt ?? this.delayedAt,
    delayMinutes: delayMinutes ?? this.delayMinutes, delayNote: delayNote ?? this.delayNote,
    cancelledAt: cancelledAt ?? this.cancelledAt,
    cancellationReason: cancellationReason ?? this.cancellationReason,
    noShowAt: noShowAt ?? this.noShowAt,
  );

  @override
  bool operator ==(Object other) => other is ReservationModel && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

class ReservationStatusHistoryModel {
  final String? previousStatus;
  final String newStatus;
  final DateTime changedAt;
  final int? delayMinutes;
  final String? note;

  const ReservationStatusHistoryModel({
    this.previousStatus, required this.newStatus, required this.changedAt,
    this.delayMinutes, this.note,
  });

  factory ReservationStatusHistoryModel.fromJson(Map<String, dynamic> json) =>
      ReservationStatusHistoryModel(
        previousStatus: json['previous_status']?.toString(),
        newStatus: (json['new_status'] ?? 'pending').toString(),
        changedAt: _parseReservationDateTime(json['changed_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        delayMinutes: (json['delay_minutes'] as num?)?.toInt(),
        note: json['note']?.toString(),
      );
}
