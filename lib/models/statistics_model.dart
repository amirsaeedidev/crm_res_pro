class DashboardBreakdownItem {
  final String label;
  final int count;
  final int quantity;
  final double amount;
  final String? mode;

  const DashboardBreakdownItem({
    required this.label,
    this.count = 0,
    this.quantity = 0,
    this.amount = 0,
    this.mode,
  });

  factory DashboardBreakdownItem.fromJson(
    Map<String, dynamic> json, {
    required String labelKey,
  }) {
    return DashboardBreakdownItem(
      label: json[labelKey]?.toString() ?? '—',
      count: StatisticsModel._toInt(json['usage_count'] ?? json['orders']),
      quantity: StatisticsModel._toInt(json['quantity']),
      amount: StatisticsModel._toDouble(
        json['total_amount'] ??
            json['discount_amount'] ??
            json['sales'],
      ),
      mode: json['payment_mode']?.toString(),
    );
  }
}

class StatisticsModel {
  final double totalSales;
  final double averageOrderAmount;
  final int totalOrders;
  final int todayOrders;
  final int inProgressOrders;
  final int completedOrders;
  final int cancelledOrders;
  final int totalCustomers;
  final int newCustomers;
  final int activeCustomers;
  final double walletBalanceTotal;
  final int loyaltyPointsTotal;
  final int discountUsageCount;
  final double totalDiscountAmount;
  final List<DashboardBreakdownItem> topProducts;
  final List<DashboardBreakdownItem> topCategories;
  final List<DashboardBreakdownItem> topDiscountCodes;
  final List<DashboardBreakdownItem> paymentBreakdown;
  final DateTime updatedAt;

  // Kept for compatibility with older dashboard widgets.
  final int totalProducts;
  final double salesGrowthPercentage;
  final double ordersGrowthPercentage;
  final double customersGrowthPercentage;
  final String period;

  const StatisticsModel({
    required this.totalSales,
    required this.averageOrderAmount,
    required this.totalOrders,
    required this.todayOrders,
    required this.inProgressOrders,
    required this.completedOrders,
    required this.cancelledOrders,
    required this.totalCustomers,
    required this.newCustomers,
    required this.activeCustomers,
    required this.walletBalanceTotal,
    required this.loyaltyPointsTotal,
    required this.discountUsageCount,
    required this.totalDiscountAmount,
    required this.topProducts,
    required this.topCategories,
    required this.topDiscountCodes,
    required this.paymentBreakdown,
    required this.updatedAt,
    this.totalProducts = 0,
    this.salesGrowthPercentage = 0,
    this.ordersGrowthPercentage = 0,
    this.customersGrowthPercentage = 0,
    this.period = 'filtered',
  });

  factory StatisticsModel.fromJson(Map<String, dynamic> json) {
    final sales = _asMap(json['sales']);
    final orders = _asMap(json['orders']);
    final customers = _asMap(json['customers']);
    final discounts = _asMap(json['discounts']);
    final updatedAtValue = json['updated_at'];
    final parsedUpdatedAt = updatedAtValue is String
        ? DateTime.tryParse(updatedAtValue)
        : updatedAtValue is DateTime
            ? updatedAtValue
            : null;

    if (parsedUpdatedAt == null) {
      throw const FormatException(
        'فیلد updated_at در پاسخ آمار داشبورد معتبر نیست.',
      );
    }

    return StatisticsModel(
      totalSales: _toDouble(sales['total']),
      averageOrderAmount: _toDouble(sales['average_order']),
      totalOrders: _toInt(orders['total']),
      todayOrders: _toInt(orders['today']),
      inProgressOrders: _toInt(orders['in_progress']),
      completedOrders: _toInt(orders['completed']),
      cancelledOrders: _toInt(orders['cancelled']),
      totalCustomers: _toInt(customers['total']),
      newCustomers: _toInt(customers['new']),
      activeCustomers: _toInt(customers['active']),
      walletBalanceTotal: _toDouble(json['wallet_balance_total']),
      loyaltyPointsTotal: _toInt(json['loyalty_points_total']),
      discountUsageCount: _toInt(discounts['usage_count']),
      totalDiscountAmount: _toDouble(discounts['total_discount_amount']),
      topProducts: _mapList(json['top_products'])
          .map((item) => DashboardBreakdownItem.fromJson(
                item,
                labelKey: 'product_name',
              ))
          .toList(growable: false),
      topCategories: _mapList(json['top_categories'])
          .map((item) => DashboardBreakdownItem.fromJson(
                item,
                labelKey: 'category_name',
              ))
          .toList(growable: false),
      topDiscountCodes: _mapList(discounts['top_codes'])
          .map((item) => DashboardBreakdownItem.fromJson(
                item,
                labelKey: 'code',
              ))
          .toList(growable: false),
      paymentBreakdown: _mapList(json['payments'])
          .map((item) => DashboardBreakdownItem.fromJson(
                item,
                labelKey: 'payment_mode',
              ))
          .toList(growable: false),
      updatedAt: parsedUpdatedAt,
    );
  }

  static Map<String, dynamic> _asMap(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  static int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
