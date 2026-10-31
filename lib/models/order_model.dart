class OrderModel {
  final String id;
  final String userId;
  final String customerName;
  final String customerPhone;
  final String orderType;
  final String status;
  final String? assignedStaffId;
  final double totalAmount;
  final double subtotalAmount;
  final double discountAmount;
  final String? discountCode;
  final int? tableNumber;
  final String? tableId;
  final int? dailyQueueNumber;
  final int? estimatedReadyMinutes;
  final String? adminNote;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<OrderItem> items;

  const OrderModel({required this.id, required this.userId, required this.customerName,
    required this.customerPhone, required this.orderType, required this.status,
    required this.totalAmount, this.subtotalAmount = 0, this.discountAmount = 0, this.discountCode,
    this.tableNumber, this.tableId, this.dailyQueueNumber, this.assignedStaffId, this.estimatedReadyMinutes, this.adminNote, this.completedAt,
    required this.createdAt, this.updatedAt, required this.items});

  factory OrderModel.fromJson(Map<String, dynamic> json) => OrderModel(
    id: json['id'].toString(), userId: (json['user_id'] ?? '').toString(),
    customerName: (json['customer_name'] ?? '').toString(), customerPhone: (json['customer_phone'] ?? '').toString(),
    orderType: (json['order_type'] ?? 'delivery').toString(), status: (json['status'] ?? 'pending').toString(),
    assignedStaffId: json['assigned_staff_id']?.toString(),
    totalAmount: (json['total_amount'] as num? ?? 0).toDouble(),
    subtotalAmount: (json['subtotal_amount'] as num? ?? json['total_amount'] as num? ?? 0).toDouble(),
    discountAmount: (json['discount_amount'] as num? ?? 0).toDouble(),
    discountCode: json['discount_code']?.toString(),
    tableNumber: (json['table_number'] as num?)?.toInt(),
    tableId: json['table_id']?.toString(),
    dailyQueueNumber: (json['daily_queue_number'] as num?)?.toInt(),
    estimatedReadyMinutes: (json['estimated_ready_minutes'] as num?)?.toInt(), adminNote: json['admin_note'] as String?,
    completedAt: DateTime.tryParse((json['completed_at'] ?? '').toString()),
    createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()),
    items: (json['order_items'] as List<dynamic>? ?? json['items'] as List<dynamic>? ?? [])
      .whereType<Map>().map((e) => OrderItem.fromJson(Map<String, dynamic>.from(e))).toList(growable: false));

  OrderModel copyWith({String? id, String? userId, String? customerName, String? customerPhone,
    String? orderType, String? status, String? assignedStaffId, double? totalAmount, int? estimatedReadyMinutes,
    String? adminNote, DateTime? completedAt, DateTime? createdAt, DateTime? updatedAt, List<OrderItem>? items,
    double? subtotalAmount, double? discountAmount, String? discountCode, int? tableNumber, int? dailyQueueNumber}) => OrderModel(
      id: id ?? this.id, userId: userId ?? this.userId, customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone, orderType: orderType ?? this.orderType,
      status: status ?? this.status, assignedStaffId: assignedStaffId ?? this.assignedStaffId, totalAmount: totalAmount ?? this.totalAmount,
      subtotalAmount: subtotalAmount ?? this.subtotalAmount, discountAmount: discountAmount ?? this.discountAmount,
      discountCode: discountCode ?? this.discountCode, tableNumber: tableNumber ?? this.tableNumber,
      tableId: tableId ?? this.tableId, dailyQueueNumber: dailyQueueNumber ?? this.dailyQueueNumber,
      estimatedReadyMinutes: estimatedReadyMinutes ?? this.estimatedReadyMinutes, adminNote: adminNote ?? this.adminNote,
      completedAt: completedAt ?? this.completedAt, createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt, items: items ?? this.items);

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'customer_name': customerName,
    'customer_phone': customerPhone,
    'order_type': orderType,
    'status': status,
    'assigned_staff_id': assignedStaffId,
    'total_amount': totalAmount,
    'subtotal_amount': subtotalAmount,
    'discount_amount': discountAmount,
    'discount_code': discountCode,
    'table_number': tableNumber,
    'table_id': tableId,
    'daily_queue_number': dailyQueueNumber,
    'estimated_ready_minutes': estimatedReadyMinutes,
    'admin_note': adminNote,
    'completed_at': completedAt?.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt?.toUtc().toIso8601String(),
    'order_items': items.map((item) => item.toJson()).toList(growable: false),
  };
}

class OrderItem {
  final String? productId;
  final String name;
  final int quantity;
  final double price;
  final double? totalPrice;
  final String? note;

  const OrderItem({this.productId, required this.name, required this.quantity, required this.price, this.totalPrice, this.note});

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    final relation = json['products'];
    return OrderItem(
      productId: json['product_id']?.toString(),
      name: (json['name'] ?? (relation is Map ? relation['name'] : null) ?? 'محصول حذف‌شده').toString(),
      quantity: (json['quantity'] as num? ?? 1).toInt(),
      price: (json['unit_price'] as num? ?? json['price'] as num? ?? 0).toDouble(),
      totalPrice: (json['total_price'] as num?)?.toDouble(), note: json['note'] as String?);
  }

  Map<String, dynamic> toJson() => {'product_id': productId, 'name': name, 'quantity': quantity,
    'unit_price': price, 'total_price': totalPrice ?? price * quantity};
}
