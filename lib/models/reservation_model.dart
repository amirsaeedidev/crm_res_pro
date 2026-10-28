enum ReservationStatus { pending, confirmed, completed, cancelled }

extension ReservationStatusX on ReservationStatus {
  String get name => switch (this) {
    ReservationStatus.pending => 'pending',
    ReservationStatus.confirmed => 'confirmed',
    ReservationStatus.completed => 'completed',
    ReservationStatus.cancelled => 'cancelled',
  };

  static ReservationStatus fromString(String? value) => switch (value?.toLowerCase()) {
    'confirmed' => ReservationStatus.confirmed,
    'completed' || 'seated' => ReservationStatus.completed,
    'cancelled' => ReservationStatus.cancelled,
    _ => ReservationStatus.pending,
  };
}

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

  const ReservationModel({required this.id, this.userId, this.tableId,
    required this.customerName, required this.customerPhone, required this.date,
    required this.time, required this.partySize, required this.tableNumber,
    this.note, this.status = ReservationStatus.pending, this.createdAt});

  factory ReservationModel.fromJson(Map<String, dynamic> json) {
    final created = DateTime.tryParse((json['created_at'] ?? '').toString());
    final dateString = (json['date'] ?? json['reservation_date'] ?? '').toString();
    final timeString = (json['time'] ?? json['reservation_time'] ?? '').toString();
    return ReservationModel(
      id: json['id'].toString(), userId: json['user_id']?.toString(), tableId: json['table_id']?.toString(),
      customerName: (json['customer_name'] ?? '').toString(), customerPhone: (json['customer_phone'] ?? '').toString(),
      date: DateTime.tryParse(dateString) ?? created ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      time: timeString.isEmpty ? (created == null ? '—' : '${created.hour.toString().padLeft(2,'0')}:${created.minute.toString().padLeft(2,'0')}') : timeString.substring(0, timeString.length >= 5 ? 5 : timeString.length),
      partySize: (json['party_size'] as num? ?? json['guest_count'] as num? ?? 1).toInt(),
      tableNumber: (json['table_number'] ?? '').toString(), note: json['note'] as String?,
      status: ReservationStatusX.fromString(json['status'] as String?), createdAt: created,
    );
  }

  ReservationModel copyWith({String? id, String? userId, String? tableId, String? customerName,
    String? customerPhone, DateTime? date, String? time, int? partySize, String? tableNumber,
    String? note, ReservationStatus? status, DateTime? createdAt}) => ReservationModel(
      id: id ?? this.id, userId: userId ?? this.userId, tableId: tableId ?? this.tableId,
      customerName: customerName ?? this.customerName, customerPhone: customerPhone ?? this.customerPhone,
      date: date ?? this.date, time: time ?? this.time, partySize: partySize ?? this.partySize,
      tableNumber: tableNumber ?? this.tableNumber, note: note ?? this.note, status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt);

  @override
  bool operator ==(Object other) => other is ReservationModel && other.id == id;
  @override
  int get hashCode => id.hashCode;
}
