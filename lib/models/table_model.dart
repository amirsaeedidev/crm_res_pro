enum TableStatus { free, occupied, reserved }

extension TableStatusX on TableStatus {
  String get name => switch (this) {
    TableStatus.free => 'free', TableStatus.occupied => 'occupied', TableStatus.reserved => 'reserved',
  };
  static TableStatus fromString(String? value) => switch (value?.toLowerCase()) {
    'occupied' => TableStatus.occupied, 'reserved' => TableStatus.reserved, _ => TableStatus.free,
  };
}

class TableModel {
  final String id;
  final String tableNumber;
  final int capacity;
  final TableStatus status;
  final String? currentOrderId;
  final bool isActive;
  final bool isOccupied;

  const TableModel({required this.id, required this.tableNumber, required this.capacity,
    this.status = TableStatus.free, this.currentOrderId, this.isActive = true, this.isOccupied = false});

  factory TableModel.fromJson(Map<String, dynamic> json) {
    final occupied = json['is_occupied'] as bool? ?? (json['status'] == 'occupied');
    final status = json['status'] != null ? TableStatusX.fromString(json['status'].toString()) : (occupied ? TableStatus.occupied : TableStatus.free);
    return TableModel(id: json['id'].toString(), tableNumber: (json['table_number'] ?? '').toString(),
      capacity: (json['capacity'] as num? ?? 2).toInt(), status: status,
      currentOrderId: json['current_order_id']?.toString(), isActive: json['is_active'] as bool? ?? true,
      isOccupied: occupied);
  }

  TableModel copyWith({String? id, String? tableNumber, int? capacity, TableStatus? status,
    String? currentOrderId, bool? isActive, bool? isOccupied}) => TableModel(
      id: id ?? this.id, tableNumber: tableNumber ?? this.tableNumber, capacity: capacity ?? this.capacity,
      status: status ?? this.status, currentOrderId: currentOrderId ?? this.currentOrderId,
      isActive: isActive ?? this.isActive, isOccupied: isOccupied ?? this.isOccupied);

  @override
  bool operator ==(Object other) => other is TableModel && other.id == id;
  @override
  int get hashCode => id.hashCode;
}
