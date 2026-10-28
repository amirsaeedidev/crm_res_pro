class LoyaltyWalletModel {
  final String id;
  final String userId;
  final String customerName;
  final String customerPhone;
  final int totalPoints;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const LoyaltyWalletModel({
    required this.id,
    required this.userId,
    required this.customerName,
    required this.customerPhone,
    required this.totalPoints,
    this.createdAt,
    this.updatedAt,
  });

  factory LoyaltyWalletModel.fromJson(Map<String, dynamic> json) =>
      LoyaltyWalletModel(
        id: (json['id'] ?? '').toString(),
        userId: (json['user_id'] ?? json['user_identifier'] ?? '').toString(),
        customerName: (json['customer_name'] ?? '').toString().trim(),
        customerPhone: (json['customer_phone'] ?? '').toString(),
        totalPoints: (json['total_points'] as num? ?? 0).toInt(),
        createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
        updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()),
      );
}

class LoyaltyTransactionModel {
  final String id;
  final String walletId;
  final String? orderId;
  final int points;
  final String type;
  final String description;
  final DateTime? createdAt;

  const LoyaltyTransactionModel({
    required this.id,
    required this.walletId,
    this.orderId,
    required this.points,
    required this.type,
    required this.description,
    this.createdAt,
  });

  factory LoyaltyTransactionModel.fromJson(Map<String, dynamic> json) =>
      LoyaltyTransactionModel(
        id: (json['id'] ?? '').toString(),
        walletId: (json['wallet_id'] ?? '').toString(),
        orderId: json['order_id']?.toString(),
        points: (json['points'] as num? ?? 0).toInt(),
        type: (json['transaction_type'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
      );
}
