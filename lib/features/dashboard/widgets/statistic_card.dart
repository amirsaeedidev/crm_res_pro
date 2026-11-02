import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_card.dart';

class StatisticCard extends StatelessWidget {
  final String title;
  final String value;
  final List<List<dynamic>> icon;
  final Color iconColor;
  final String changePercentage;
  final bool isPositiveChange;
  final bool isFeatured;

  const StatisticCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.changePercentage,
    this.isPositiveChange = true,
    this.isFeatured = false,
  });

  @override
  Widget build(BuildContext context) {
    final parsedChange = double.tryParse(changePercentage.replaceAll(',', '.')) ?? 0;
    final positive = parsedChange >= 0;
    final trendColor = positive ? AppColors.success : AppColors.error;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              HugeIcon(
                icon: icon,
                color: iconColor,
                size: isFeatured ? 44 : 34,
                strokeWidth: 1.8,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: trendColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.circular),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      positive ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 12,
                      color: trendColor,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '$changePercentage%',
                      style: AppTypography.labelSmall.copyWith(
                        color: trendColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: isFeatured ? AppSizes.lg : AppSizes.md),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.headlineMedium.copyWith(
              fontSize: isFeatured ? 30 : null,
              color: AppColors.getPrimaryText(context),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSizes.xs),
          SizedBox(
            height: isFeatured ? 42 : 30,
            width: double.infinity,
            child: CustomPaint(
              painter: _TrendLinePainter(color: trendColor, positive: positive),
            ),
          ),
          const SizedBox(height: AppSizes.xs),
          Text(
            title,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.getSecondaryText(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendLinePainter extends CustomPainter {
  final Color color;
  final bool positive;

  const _TrendLinePainter({required this.color, required this.positive});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final start = Offset(2, positive ? size.height * 0.78 : size.height * 0.22);
    final end = Offset(size.width - 2, positive ? size.height * 0.22 : size.height * 0.78);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(end.dx, end.dy);
    canvas.drawPath(path, paint);
    canvas.drawCircle(end, 2.8, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TrendLinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.positive != positive;
}
