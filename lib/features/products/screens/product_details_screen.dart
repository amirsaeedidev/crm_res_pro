import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../models/product_model.dart';
import '../../../providers/products_provider.dart';
import '../../../repositories/products_repository.dart';

class ProductDetailsScreen extends StatefulWidget {
  final String productId;
  const ProductDetailsScreen({super.key, required this.productId});
  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}
class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  late Future<ProductModel> _productFuture;
  @override
  void initState() { super.initState(); _productFuture = context.read<ProductsRepository>().getProductById(widget.productId); }

  Future<void> _delete(ProductModel product) async {
    final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('حذف محصول'), content: Text('محصول «${product.name}» حذف شود؟ سفارش‌های قبلی ممکن است مانع حذف آن شوند.'), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف'))]));
    if (yes != true || !mounted) return;
    final provider = context.read<ProductsProvider>();
    final ok = await provider.deleteProduct(product.id);
    if (!mounted) return;
    if (ok) {
      await provider.fetchProducts();
      if (mounted) context.go('/products');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(provider.error ?? 'حذف محصول ناموفق بود.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('جزئیات محصول')), body: FutureBuilder<ProductModel>(future: _productFuture, builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
    if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text('دریافت محصول ناموفق بود: ${snapshot.error}', textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton(onPressed: () => setState(() => _productFuture = context.read<ProductsRepository>().getProductById(widget.productId)), child: const Text('تلاش مجدد'))])));
    final product = snapshot.data;
    if (product == null) return const Center(child: Text('محصول پیدا نشد.'));
    return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 800), child: ListView(padding: const EdgeInsets.all(20), children: [
      if (product.imageUrl.isNotEmpty) ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.network(product.imageUrl, height: 260, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(height: 140, child: Icon(Icons.broken_image_outlined, size: 48)))),
      const SizedBox(height: 16), Text(product.name, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      if (product.discountedPrice != null && product.discountedPrice! < product.price) ...[
        Text('${product.price.toStringAsFixed(0)} تومان', style: Theme.of(context).textTheme.bodyMedium?.copyWith(decoration: TextDecoration.lineThrough, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        Text('${product.discountedPrice!.toStringAsFixed(0)} تومان  (${product.discountPercent.toStringAsFixed(product.discountPercent % 1 == 0 ? 0 : 2)}٪ تخفیف)', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.bold)),
      ] else Text('${product.price.toStringAsFixed(0)} تومان', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12), Text(product.description.isEmpty ? 'توضیحی ثبت نشده است.' : product.description),
      if (product.aboutDish.trim().isNotEmpty) ...[const SizedBox(height: 12), Text('درباره این غذا', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(product.aboutDish)],
      if (product.labels.isNotEmpty) ...[const SizedBox(height: 12), Text('لیبل‌ها', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 6), Wrap(spacing: 6, runSpacing: 6, children: product.labels.map((label) => Chip(label: Text(label))).toList())],
      const SizedBox(height: 12), Text('دسته‌بندی: ${product.categoryName ?? 'بدون دسته‌بندی'}'), Text('وضعیت: ${product.status == 'active' ? 'فعال' : 'غیرفعال'}'), Text('محبوب: ${product.isPopular ? 'بله' : 'خیر'}'), Text('شناسه: ${product.id}'),
      const SizedBox(height: 24), Wrap(spacing: 12, children: [FilledButton.icon(onPressed: () => context.push('/products/edit/${product.id}'), icon: const Icon(Icons.edit_outlined), label: const Text('ویرایش')), OutlinedButton.icon(onPressed: () => _delete(product), icon: const Icon(Icons.delete_outline), label: const Text('حذف'))])
    ])));
  }));
}
