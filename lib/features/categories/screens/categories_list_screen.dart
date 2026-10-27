import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
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
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) context.read<CategoriesProvider>().fetchCategories(); }); }
  @override
  void dispose() { _searchController.dispose(); super.dispose(); }

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
    final approved = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('حذف دسته‌بندی'), content: Text('دسته‌بندی «${category.name}» حذف شود؟ اگر محصولی به آن وابسته باشد، دیتابیس حذف را رد می‌کند.'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حذف'))],
    ));
    if (approved != true || !mounted) return;
    final provider = context.read<CategoriesProvider>();
    final ok = await provider.deleteCategory(category.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'دسته‌بندی حذف شد.' : provider.error ?? 'حذف ناموفق بود.')));
    if (ok) provider.fetchCategories();
  }

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Expanded(child: Text('مدیریت دسته‌بندی‌ها', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold))), FilledButton.icon(onPressed: () => context.push('/categories/add'), icon: const Icon(Icons.add), label: const Text('دسته‌بندی جدید'))]),
    const SizedBox(height: 16), TextField(controller: _searchController, decoration: InputDecoration(labelText: 'جست‌وجو بر اساس نام', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(onPressed: () { _searchController.clear(); context.read<CategoriesProvider>().setSearchQuery(''); }, icon: const Icon(Icons.clear)), border: const OutlineInputBorder()), onSubmitted: (v) => context.read<CategoriesProvider>().setSearchQuery(v)),
    const SizedBox(height: 12), Expanded(child: Consumer<CategoriesProvider>(builder: (context, provider, _) {
      if (provider.isLoading && provider.categories.isEmpty) return const Center(child: CircularProgressIndicator());
      if (provider.error != null && provider.categories.isEmpty) return _error(provider.error!, provider.fetchCategories);
      if (provider.categories.isEmpty) return const Center(child: Text('هیچ دسته‌بندی‌ای در دیتابیس ثبت نشده است.'));
      return Column(children: [Expanded(child: ListView.separated(itemCount: provider.categories.length, separatorBuilder: (_, _) => const SizedBox(height: 8), itemBuilder: (context, index) {
        final category = provider.categories[index];
        return Card(child: ListTile(leading: category.imageUrl == null || category.imageUrl!.isEmpty ? const CircleAvatar(child: Icon(Icons.category_outlined)) : CircleAvatar(backgroundImage: NetworkImage(category.imageUrl!)), title: Text(category.name), subtitle: Text('ترتیب نمایش: ${_persianDigits(category.displayOrder)} • امتیاز هر محصول: ${_persianDigits(category.loyaltyPointsPerItem)}'), trailing: Wrap(spacing: 0, children: [Switch(value: category.isActive, onChanged: (value) async { final ok = await provider.updateCategory(category.id, {'is_active': value}); if (!context.mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'وضعیت ذخیره شد.' : provider.error ?? 'ذخیره ناموفق بود.'))); }), IconButton(tooltip: 'ویرایش', onPressed: () => context.push('/categories/edit/${category.id}'), icon: const Icon(Icons.edit_outlined)), IconButton(tooltip: 'حذف', onPressed: () => _delete(category), icon: const Icon(Icons.delete_outline, color: Colors.red))])));
      })), Row(mainAxisAlignment: MainAxisAlignment.center, children: [IconButton(onPressed: provider.currentPage > 1 ? () => provider.changePage(provider.currentPage - 1) : null, icon: const Icon(Icons.chevron_right)), Text('صفحه ${_persianDigits(provider.currentPage)}'), IconButton(onPressed: provider.categories.length == 15 ? () => provider.changePage(provider.currentPage + 1) : null, icon: const Icon(Icons.chevron_left))])]);
    }))
  ]));

  Widget _error(String message, Future<void> Function() retry) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off_outlined, size: 44), const SizedBox(height: 8), Text(message, textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton.icon(onPressed: retry, icon: const Icon(Icons.refresh), label: const Text('تلاش مجدد'))])));
}
