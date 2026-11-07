import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:crm_panel/core/constants/app_colors.dart';
import 'package:crm_panel/features/dashboard/widgets/statistic_card.dart';

void main() {
  testWidgets('StatisticCard displays title, value, and percentage correctly',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatisticCard(
            title: 'فروش کل',
            value: '45,200,000 T',
            icon: HugeIcons.strokeRoundedWallet01,
            iconColor: AppColors.success,
            changePercentage: '12',
          ),
        ),
      ),
    );

    expect(find.text('فروش کل'), findsOneWidget);
    expect(find.text('45,200,000 T'), findsOneWidget);
    expect(find.text('12%'), findsOneWidget);
    expect(find.byType(HugeIcon), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
  });

  testWidgets('StatisticCard displays negative growth correctly',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatisticCard(
            title: 'سفارشات لغو شده',
            value: '15',
            icon: HugeIcons.strokeRoundedShoppingBag01,
            iconColor: AppColors.error,
            changePercentage: '-5',
          ),
        ),
      ),
    );

    expect(find.text('سفارشات لغو شده'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
    expect(find.text('-5%'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
  });
}
