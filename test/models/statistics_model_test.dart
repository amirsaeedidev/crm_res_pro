import 'package:flutter_test/flutter_test.dart';
import 'package:crm_panel/models/statistics_model.dart';

void main() {
  group('StatisticsModel', () {
    test('maps the filtered CRM dashboard response', () {
      final model = StatisticsModel.fromJson({
        'updated_at': '2026-11-07T10:00:00.000Z',
        'customers': {'total': 12, 'new': 3, 'active': 8},
        'orders': {
          'total': 20,
          'today': 4,
          'in_progress': 5,
          'completed': 12,
          'cancelled': 3,
        },
        'sales': {'total': 540000, 'average_order': 45000},
        'top_products': [
          {
            'product_id': 'p1',
            'product_name': 'پیتزا',
            'quantity': 9,
            'total_amount': 405000,
          },
        ],
        'top_categories': [
          {
            'category_id': 'c1',
            'category_name': 'غذا',
            'quantity': 9,
            'total_amount': 405000,
          },
        ],
        'discounts': {
          'usage_count': 4,
          'total_discount_amount': 80000,
          'top_codes': [
            {
              'code': 'WELCOME',
              'usage_count': 4,
              'discount_amount': 80000,
            },
          ],
        },
        'wallet_balance_total': 9000000,
        'loyalty_points_total': 250,
        'payments': [
          {'payment_mode': 'mock', 'orders': 10, 'sales': 400000},
          {'payment_mode': 'real', 'orders': 2, 'sales': 140000},
        ],
      });

      expect(model.totalCustomers, 12);
      expect(model.newCustomers, 3);
      expect(model.activeCustomers, 8);
      expect(model.totalOrders, 20);
      expect(model.todayOrders, 4);
      expect(model.inProgressOrders, 5);
      expect(model.completedOrders, 12);
      expect(model.cancelledOrders, 3);
      expect(model.totalSales, 540000);
      expect(model.averageOrderAmount, 45000);
      expect(model.walletBalanceTotal, 9000000);
      expect(model.loyaltyPointsTotal, 250);
      expect(model.discountUsageCount, 4);
      expect(model.topProducts.single.label, 'پیتزا');
      expect(model.topProducts.single.quantity, 9);
      expect(model.topCategories.single.label, 'غذا');
      expect(model.topDiscountCodes.single.label, 'WELCOME');
      expect(model.paymentBreakdown, hasLength(2));
      expect(model.paymentBreakdown.first.mode, 'mock');
      expect(model.paymentBreakdown.first.count, 10);
    });

    test('rejects a dashboard response without updated_at', () {
      expect(
        () => StatisticsModel.fromJson(<String, dynamic>{}),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
