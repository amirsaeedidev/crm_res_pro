class DiscountModel {
  final String id;
  final String title;
  final String code;
  /// UI aliases: `percentage` maps to DB `percent`; `fixed_amount` maps to `fixed`.
  final String type;
  final double value;
  final double? minPurchaseAmount;
  final double? maxDiscountAmount;
  final int? totalUsageLimit;
  /// Maximum number of times one customer can redeem this code.
  final int? perUserUsageLimit;
  final bool restrictedToCustomers;
  final List<String> targetPhones;
  final int usedCount;
  final bool isActive;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? description;

  const DiscountModel({
    required this.id,
    required this.title,
    required this.code,
    required this.type,
    required this.value,
    this.minPurchaseAmount,
    this.maxDiscountAmount,
    this.totalUsageLimit,
    this.perUserUsageLimit,
    this.restrictedToCustomers = false,
    this.targetPhones = const [],
    this.usedCount = 0,
    this.isActive = true,
    required this.startDate,
    required this.endDate,
    required this.createdAt,
    this.updatedAt,
    this.description,
  });

  factory DiscountModel.fromJson(Map<String, dynamic> json) {
    final created = DateTime.tryParse((json['created_at'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final rawType = (json['discount_type'] ?? json['type'] ?? 'percent').toString();
    return DiscountModel(
      id: json['id'].toString(),
      title: (json['title'] ?? '').toString(),
      code: (json['code'] ?? '').toString(),
      type: rawType == 'percent' ? 'percentage' : (rawType == 'fixed' ? 'fixed_amount' : rawType),
      value: (json['discount_value'] as num? ?? json['value'] as num? ?? 0).toDouble(),
      minPurchaseAmount: (json['min_order_amount'] as num? ?? json['min_purchase_amount'] as num?)?.toDouble(),
      maxDiscountAmount: (json['max_discount_amount'] as num?)?.toDouble(),
      totalUsageLimit: (json['usage_limit'] as num? ?? json['total_usage_limit'] as num?)?.toInt(),
      perUserUsageLimit: (json['per_user_usage_limit'] as num?)?.toInt(),
      restrictedToCustomers: json['restricted_to_customers'] as bool? ?? false,
      targetPhones: json['target_phones'] is List ? (json['target_phones'] as List).map((e) => e.toString()).toList(growable: false) : const <String>[],
      usedCount: (json['used_count'] as num? ?? 0).toInt(),
      isActive: json['is_active'] as bool? ?? true,
      startDate: DateTime.tryParse((json['starts_at'] ?? json['start_date'] ?? '').toString()) ?? created,
      endDate: DateTime.tryParse((json['expires_at'] ?? json['end_date'] ?? '').toString()) ?? DateTime.utc(9999, 12, 31),
      createdAt: created,
      updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()),
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'code': code,
        'description': description,
        'discount_type': type == 'percentage' ? 'percent' : (type == 'fixed_amount' ? 'fixed' : type),
        'discount_value': value,
        'min_order_amount': minPurchaseAmount ?? 0,
        'max_discount_amount': maxDiscountAmount,
        'usage_limit': totalUsageLimit,
        'used_count': usedCount,
        'restricted_to_customers': restrictedToCustomers,
        'per_user_usage_limit': perUserUsageLimit,
        'is_active': isActive,
        'starts_at': startDate.toUtc().toIso8601String(),
        'expires_at': endDate.toUtc().toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
      };

  DiscountModel copyWith({
    String? id, String? title, String? code, String? type, double? value,
    double? minPurchaseAmount, double? maxDiscountAmount, int? totalUsageLimit,
    int? perUserUsageLimit, bool? restrictedToCustomers, List<String>? targetPhones, int? usedCount, bool? isActive, DateTime? startDate,
    DateTime? endDate, DateTime? createdAt, DateTime? updatedAt, String? description,
  }) => DiscountModel(
        id: id ?? this.id, title: title ?? this.title, code: code ?? this.code,
        type: type ?? this.type, value: value ?? this.value,
        minPurchaseAmount: minPurchaseAmount ?? this.minPurchaseAmount,
        maxDiscountAmount: maxDiscountAmount ?? this.maxDiscountAmount,
        totalUsageLimit: totalUsageLimit ?? this.totalUsageLimit,
        perUserUsageLimit: perUserUsageLimit ?? this.perUserUsageLimit,
        restrictedToCustomers: restrictedToCustomers ?? this.restrictedToCustomers,
        targetPhones: targetPhones ?? this.targetPhones,
        usedCount: usedCount ?? this.usedCount, isActive: isActive ?? this.isActive,
        startDate: startDate ?? this.startDate, endDate: endDate ?? this.endDate,
        createdAt: createdAt ?? this.createdAt, updatedAt: updatedAt ?? this.updatedAt,
        description: description ?? this.description,
      );
}
