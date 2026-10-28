class UserModel {
  final String id;
  final String email;
  final String? firstName;
  final String? lastName;
  final String? phone;
  final String? avatarUrl;
  final String role;
  final String status;
  final bool marketingSmsOptIn;
  final int purchaseCount;
  final double totalPurchaseAmount;
  final DateTime? lastPurchaseAt;
  final DateTime createdAt;

  UserModel({
    required this.id,
    required this.email,
    this.firstName,
    this.lastName,
    this.phone,
    this.avatarUrl,
    this.role = 'customer',
    this.status = 'active',
    this.marketingSmsOptIn = false,
    this.purchaseCount = 0,
    this.totalPurchaseAmount = 0,
    this.lastPurchaseAt,
    required this.createdAt,
  });

  /// An active admin account can access admin UI.
  /// Real data access must still be protected by Supabase RLS.
  bool get isAdmin => role == 'admin' && status == 'active';

  bool get isActive => status == 'active';

  String get fullName {
    final first = firstName?.trim();
    final last = lastName?.trim();

    if (first != null &&
        first.isNotEmpty &&
        last != null &&
        last.isNotEmpty) {
      return '$first $last';
    }

    if (first != null && first.isNotEmpty) {
      return first;
    }

    if (last != null && last.isNotEmpty) {
      return last;
    }

    return email;
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      phone: json['phone'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      role: json['role'] as String? ?? 'customer',
      status: json['status'] as String? ?? 'active',
      marketingSmsOptIn: json['marketing_sms_opt_in'] as bool? ?? false,
      purchaseCount: (json['purchase_count'] as num?)?.toInt() ?? 0,
      totalPurchaseAmount: (json['total_purchase_amount'] as num?)?.toDouble() ?? 0,
      lastPurchaseAt: DateTime.tryParse(json['last_purchase_at']?.toString() ?? ''),
      createdAt: DateTime.tryParse(
            json['created_at'] as String? ?? '',
          ) ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'first_name': firstName,
      'last_name': lastName,
      'phone': phone,
      'avatar_url': avatarUrl,
      'role': role,
      'status': status,
      'marketing_sms_opt_in': marketingSmsOptIn,
      'purchase_count': purchaseCount,
      'total_purchase_amount': totalPurchaseAmount,
      'last_purchase_at': lastPurchaseAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? firstName,
    String? lastName,
    String? phone,
    String? avatarUrl,
    String? role,
    String? status,
    bool? marketingSmsOptIn,
    int? purchaseCount,
    double? totalPurchaseAmount,
    DateTime? lastPurchaseAt,
    DateTime? createdAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      status: status ?? this.status,
      marketingSmsOptIn: marketingSmsOptIn ?? this.marketingSmsOptIn,
      purchaseCount: purchaseCount ?? this.purchaseCount,
      totalPurchaseAmount: totalPurchaseAmount ?? this.totalPurchaseAmount,
      lastPurchaseAt: lastPurchaseAt ?? this.lastPurchaseAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}