import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_card.dart';

class CategoryPieChart extends StatefulWidget {
  const CategoryPieChart({super.key});
  @override
  State<CategoryPieChart> createState() => _CategoryPieChartState();
}

class _CategoryPieChartState extends State<CategoryPieChart> {
  late Future<List<_CategoryCount>> _future;

  @override
  void initState() { super.initState(); _future = _fetchCounts(); }

  Future<List<_CategoryCount>> _fetchCounts() async {
    final rows = await SupabaseService.client.from('products').select('category_id,categories(name)').eq('is_active', true);
    final grouped = <String, int>{};
    for (final row in rows) {
      final dynamic relation = row['categories'];
      final name = (relation is Map ? relation['name'] : null)?.toString().trim();
      final label = name == null || name.isEmpty ? 'بدون دسته‌بندی' : name;
      grouped.update(label, (count) => count + 1, ifAbsent: () => 1);
    }
    final items = grouped.entries.map((e) => _CategoryCount(e.key, e.value)).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return items;
  }

  @override
  Widget build(BuildContext context) => AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('توزیع محصولات', style: AppTypography.titleLarge.copyWith(color: AppColors.getPrimaryText(context), fontWeight: FontWeight.bold)),
    const SizedBox(height: AppSizes.sm),
    Text('بر اساس تعداد محصولات فعال در دیتابیس', style: AppTypography.bodyMedium.copyWith(color: AppColors.getSecondaryText(context))),
    const SizedBox(height: AppSizes.xl),
    FutureBuilder<List<_CategoryCount>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
        if (snapshot.hasError) return SizedBox(height: 200, child: Center(child: Padding(padding: const EdgeInsets.all(12), child: Text('دریافت توزیع محصولات ناموفق بود: ${snapshot.error}', textAlign: TextAlign.center))));
        final data = snapshot.data ?? const <_CategoryCount>[];
        if (data.isEmpty) return const SizedBox(height: 150, child: Center(child: Text('محصول فعال برای نمایش وجود ندارد.')));
        final total = data.fold<int>(0, (sum, item) => sum + item.count);
        final colors = [AppColors.primary, AppColors.secondary, AppColors.accent, AppColors.success, AppColors.info];
        return Column(children: [
          SizedBox(height: 210, child: PieChart(PieChartData(
            sectionsSpace: 2, centerSpaceRadius: 38,
            sections: List.generate(data.length, (index) {
              final item = data[index];
              final percent = total == 0 ? 0 : item.count * 100 / total;
              return PieChartSectionData(color: colors[index % colors.length], value: item.count.toDouble(), title: '${percent.toStringAsFixed(0)}%', radius: 48,
                titleStyle: AppTypography.labelMedium.copyWith(color: Colors.white, fontWeight: FontWeight.bold));
            }),
          ))),
          const SizedBox(height: AppSizes.md),
          Wrap(spacing: AppSizes.md, runSpacing: AppSizes.sm, children: List.generate(data.length, (index) => _legend(context, colors[index % colors.length], '${data[index].name} (${data[index].count})'))),
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => setState(() => _future = _fetchCounts()), icon: const Icon(Icons.refresh), label: const Text('به‌روزرسانی'))),
        ]);
      },
    ),
  ]));

  Widget _legend(BuildContext context, Color color, String label) => Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: AppSizes.xs), Text(label, style: AppTypography.bodyMedium.copyWith(color: AppColors.getSecondaryText(context)))]);
}

class _CategoryCount {
  final String name;
  final int count;
  const _CategoryCount(this.name, this.count);
}
