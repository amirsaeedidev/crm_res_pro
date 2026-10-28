class CustomerWalletModel {
  final String id;
  final String userId;
  final String customerName;
  final String customerPhone;
  final String? email;
  final double balance;
  final String currency;
  final DateTime? updatedAt;

  const CustomerWalletModel({
    required this.id,
    required this.userId,
    required this.customerName,
    required this.customerPhone,
    this.email,
    required this.balance,
    required this.currency,
    this.updatedAt,
  });

  factory CustomerWalletModel.fromJson(Map<String, dynamic> json) => CustomerWalletModel(
        id: (json['id'] ?? '').toString(),
        userId: (json['user_id'] ?? '').toString(),
        customerName: (json['customer_name'] ?? 'مشتری بدون نام').toString(),
        customerPhone: (json['customer_phone'] ?? '').toString(),
        email: json['email']?.toString(),
        balance: (json['balance'] as num? ?? 0).toDouble(),
        currency: (json['currency'] ?? 'IRR').toString(),
        updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()),
      );
}

class CustomerWalletTransactionModel {
  final String id;
  final double amountDelta;
  final double balanceAfter;
  final String type;
  final String reason;
  final DateTime? createdAt;

  const CustomerWalletTransactionModel({
    required this.id,
    required this.amountDelta,
    required this.balanceAfter,
    required this.type,
    required this.reason,
    this.createdAt,
  });

  factory CustomerWalletTransactionModel.fromJson(Map<String, dynamic> json) => CustomerWalletTransactionModel(
        id: (json['id'] ?? '').toString(),
        amountDelta: (json['amount_delta'] as num? ?? 0).toDouble(),
        balanceAfter: (json['balance_after'] as num? ?? 0).toDouble(),
        type: (json['transaction_type'] ?? 'adjustment').toString(),
        reason: (json['reason'] ?? '').toString(),
        createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
      );
}
