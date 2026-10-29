import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/widgets/app_card.dart';
import '../../../models/category_model.dart';
import '../../../providers/categories_provider.dart';

class CategoriesListScreen extends StatefulWidget {
  const CategoriesListScreen({super.key});

  @override
  State<CategoriesListScreen> createState() => _CategoriesListScreenState();
}

class _CategoriesListScreenState extends State<CategoriesListScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CategoriesProvider>().fetchCategories();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _persianDigits(Object? value) {
    const latin = '0123456789';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    var result = value?.toString() ?? '';
    for (var i = 0; i < latin.length; i++) {
      result = result.replaceAll(latin[i], persian[i]);
    }
    return result;
  }

  Future<void> _delete(CategoryModel category) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف دسته‌بندی'),
        content: Text(
          'دسته‌بندی «${category.name}» حذف شود؟ اگر محصولی به آن وابسته باشد، دیتابیس حذف را رد می‌کند.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('انصراف'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('حذف دسته‌بندی'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;

    final provider = context.read<CategoriesProvider>();
    final ok = await provider.deleteCategory(category.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'دسته‌بندی حذف شد.' : provider.error ?? 'حذف ناموفق بود.',
        ),
      ),
    );
    if (ok) provider.fetchCategories();
  }

  Future<void> _toggleActive(CategoryModel category, bool value) async {
    final provider = context.read<CategoriesProvider>();
    final ok = await provider.updateCategory(
      category.id,
      {'is_active': value},
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'وضعیت دسته‌بندی ذخیره شد.' : provider.error ?? 'ذخیره ناموفق بود.',
        ),
      ),
    );
  }

  Widget _statusLabel(bool active) {
    final color = active ? AppColors.success : AppColors.getSecondaryText(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadius.circularAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.check_circle_outline : Icons.visibility_off_outlined,
            size: 13,
            color: color,
          ),
          const SizedBox(width: AppSizes.xs),
          Text(
            active ? 'فعال' : 'غیرفعال',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(AppSizes.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: AppRadius.mediumAll,
                  ),
                  child: const Icon(
                    Icons.category_outlined,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: Text(
                    'مدیریت دسته‌بندی‌ها',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => context.push('/categories/add'),
                  icon: const Icon(Icons.add),
                  label: const Text('دسته‌بندی جدید'),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.md),
            AppCard(
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onChanged: (value) =>
                    context.read<CategoriesProvider>().setSearchQuery(value),
                decoration: InputDecoration(
                  labelText: 'جست‌وجوی دسته‌بندی',
                  hintText: 'نام دسته‌بندی را وارد کنید',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'پاک کردن جست‌وجو',
                    onPressed: () {
                      _searchController.clear();
                      context.read<CategoriesProvider>().setSearchQuery('');
                    },
                    icon: const Icon(Icons.clear),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSizes.md),
            Expanded(
              child: Consumer<CategoriesProvider>(
                builder: (context, provider, _) {
                  if (provider.isLoading && provider.categories.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (provider.error != null && provider.categories.isEmpty) {
                    return _error(provider.error!, provider.fetchCategories);
                  }
                  if (provider.categories.isEmpty) {
                    return const Center(
                      child: Text('هیچ دسته‌بندی‌ای در دیتابیس ثبت نشده است.'),
                    );
                  }

                  return Column(
                    children: [
                      Expanded(
                        child: ListView.separated(
                          itemCount: provider.categories.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSizes.sm),
                          itemBuilder: (context, index) {
                            final category = provider.categories[index];
                            return AppCard(
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: AppRadius.mediumAll,
                                    child: category.imageUrl == null ||
                                            category.imageUrl!.isEmpty
                                        ? Container(
                                            width: 52,
                                            height: 52,
                                            color: AppColors.primary
                                                .withValues(alpha: 0.10),
                                            child: const Icon(
                                              Icons.category_outlined,
                                              color: AppColors.primary,
                                            ),
                                          )
                                        : Image.network(
                                            category.imageUrl!,
                                            width: 52,
                                            height: 52,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) => Container(
                                              width: 52,
                                              height: 52,
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.10),
                                              child: const Icon(
                                                Icons.broken_image_outlined,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          ),
                                  ),
                                  const SizedBox(width: AppSizes.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          category.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        const SizedBox(height: AppSizes.xs),
                                        Wrap(
                                          spacing: AppSizes.xs,
                                          runSpacing: AppSizes.xs,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            _statusLabel(category.isActive),
                                            Text(
                                              'ترتیب: ${_persianDigits(category.displayOrder)}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: AppColors
                                                        .getSecondaryText(context),
                                                  ),
                                            ),
                                            Text(
                                              'امتیاز هر محصول: ${_persianDigits(category.loyaltyPointsPerItem)}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: AppColors
                                                        .getSecondaryText(context),
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: AppSizes.xs),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Switch.adaptive(
                                        value: category.isActive,
                                        onChanged: (value) =>
                                            _toggleActive(category, value),
                                      ),
                                      PopupMenuButton<String>(
                                        tooltip: 'عملیات دسته‌بندی',
                                        onSelected: (value) {
                                          if (value == 'edit') {
                                            context.push(
                                              '/categories/edit/${category.id}',
                                            );
                                          } else if (value == 'delete') {
                                            _delete(category);
                                          }
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: ListTile(
                                              dense: true,
                                              leading: Icon(Icons.edit_outlined),
                                              title: Text('ویرایش'),
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: ListTile(
                                              dense: true,
                                              leading: Icon(
                                                Icons.delete_outline,
                                                color: Colors.red,
                                              ),
                                              title: Text('حذف'),
                                            ),
                                          ),
                                        ],
                                        icon: const Icon(Icons.more_horiz),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: AppSizes.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            tooltip: 'صفحه قبلی',
                            onPressed: provider.currentPage > 1
                                ? () => provider.changePage(
                                      provider.currentPage - 1,
                                    )
                                : null,
                            icon: const Icon(Icons.chevron_right),
                          ),
                          Text('صفحه ${_persianDigits(provider.currentPage)}'),
                          IconButton(
                            tooltip: 'صفحه بعدی',
                            onPressed: provider.categories.length == 15
                                ? () => provider.changePage(
                                      provider.currentPage + 1,
                                    )
                                : null,
                            icon: const Icon(Icons.chevron_left),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      );

  Widget _error(String message, Future<void> Function() retry) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 44),
              const SizedBox(height: AppSizes.sm),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: AppSizes.md),
              FilledButton.icon(
                onPressed: retry,
                icon: const Icon(Icons.refresh),
                label: const Text('تلاش مجدد'),
              ),
            ],
          ),
        ),
      );
}
