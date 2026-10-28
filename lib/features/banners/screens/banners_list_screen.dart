import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../models/banner_model.dart';
import '../../../providers/banners_provider.dart';

class BannersListScreen extends StatefulWidget {
  const BannersListScreen({super.key});
  @override
  State<BannersListScreen> createState() => _BannersListScreenState();
}
class _BannersListScreenState extends State<BannersListScreen> {
  final _search = TextEditingController();
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) context.read<BannersProvider>().fetchBanners(); }); }
  @override
  void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _delete(BannerModel banner) async {
    final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('حذف بنر'), content: Text('بنر «${banner.title}» حذف شود؟'), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف'))]));
    if (yes != true || !mounted) return;
    final provider = context.read<BannersProvider>();
    final ok = await provider.deleteBanner(banner.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'بنر حذف شد.' : provider.error ?? 'حذف ناموفق بود.')));
  }
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Expanded(child: Text('مدیریت بنرها', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold))), FilledButton.icon(onPressed: () => context.push('/banners/add'), icon: const Icon(Icons.add), label: const Text('بنر جدید'))]),
    const SizedBox(height: 16), TextField(controller: _search, decoration: InputDecoration(labelText: 'جست‌وجوی عنوان بنر', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(onPressed: () { _search.clear(); context.read<BannersProvider>().setSearchQuery(''); }, icon: const Icon(Icons.clear)), border: const OutlineInputBorder()), onSubmitted: (v) => context.read<BannersProvider>().setSearchQuery(v)),
    const SizedBox(height: 14), Expanded(child: Consumer<BannersProvider>(builder: (context, provider, _) {
      if (provider.isLoading && provider.banners.isEmpty) return const Center(child: CircularProgressIndicator());
      if (provider.error != null && provider.banners.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(provider.error!, textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton(onPressed: provider.fetchBanners, child: const Text('تلاش مجدد'))]));
      if (provider.banners.isEmpty) return const Center(child: Text('هنوز بنری ثبت نشده است.'));
      return GridView.builder(gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 360, mainAxisExtent: 300, crossAxisSpacing: 12, mainAxisSpacing: 12), itemCount: provider.banners.length, itemBuilder: (context, index) {
        final banner = provider.banners[index];
        return Card(clipBehavior: Clip.antiAlias, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: Stack(fit: StackFit.expand, children: [
            banner.imageUrl == null || banner.imageUrl!.isEmpty
                ? const Center(child: Icon(Icons.image_outlined, size: 48))
                : Image.network(banner.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined, size: 48))),
            if (banner.logoUrl?.isNotEmpty == true) Positioned(right: 10, top: 10, child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .92), borderRadius: BorderRadius.circular(10)), child: Image.network(banner.logoUrl!, width: 46, height: 46, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(Icons.storefront_outlined, size: 40)))),
            if ((banner.promoTitle ?? '').isNotEmpty || (banner.discountCode ?? '').isNotEmpty) Positioned(left: 10, bottom: 10, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.black.withValues(alpha: .72), borderRadius: BorderRadius.circular(10)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [if ((banner.promoTitle ?? '').isNotEmpty) Text(banner.promoTitle!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), if ((banner.discountCode ?? '').isNotEmpty) Text('کد: ${banner.discountCode}', style: const TextStyle(color: Colors.white))]))),
          ])),
          Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(banner.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)), if ((banner.subtitle ?? '').isNotEmpty) Text(banner.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)])),
          Row(children: [Expanded(child: SwitchListTile(dense: true, title: Text(banner.isActive ? 'فعال' : 'غیرفعال'), value: banner.isActive, onChanged: (v) async { final ok = await provider.toggleBannerStatus(banner.id, v); if (!context.mounted) return; if (!ok) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(provider.error ?? 'ذخیره وضعیت ناموفق بود.'))); })), IconButton(onPressed: () => context.push('/banners/edit/${banner.id}'), tooltip: 'ویرایش', icon: const Icon(Icons.edit_outlined)), IconButton(onPressed: () => _delete(banner), tooltip: 'حذف', icon: const Icon(Icons.delete_outline, color: Colors.red))])
        ]));
      });
    }))
  ]));
}
