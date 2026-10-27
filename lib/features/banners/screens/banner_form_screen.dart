import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/services/upload_service.dart';
import '../../../core/utils/app_error_message.dart';
import '../../../providers/banners_provider.dart';
import '../../../repositories/banners_repository.dart';

class BannerFormScreen extends StatefulWidget {
  final String? bannerId;
  const BannerFormScreen({super.key, this.bannerId});
  @override
  State<BannerFormScreen> createState() => _BannerFormScreenState();
}

class _BannerFormScreenState extends State<BannerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _subtitle = TextEditingController();
  final _promoTitle = TextEditingController();
  final _discountCode = TextEditingController();
  final _order = TextEditingController(text: '0');
  XFile? _image;
  Uint8List? _imageBytes;
  XFile? _logo;
  Uint8List? _logoBytes;
  String? _imageUrl;
  String? _logoUrl;
  bool _active = true;
  bool _saving = false;
  bool get _editing => widget.bannerId != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final provider = context.read<BannersProvider>();
    final repository = context.read<BannersRepository>();
    if (provider.banners.isEmpty) await provider.fetchBanners();
    if (!mounted || !_editing) return;
    try {
      final banner = provider.getBannerById(widget.bannerId!) ?? await repository.getBannerById(widget.bannerId!);
      if (!mounted) return;
      setState(() {
        _title.text = banner.title;
        _subtitle.text = banner.subtitle ?? '';
        _promoTitle.text = banner.promoTitle ?? '';
        _discountCode.text = banner.discountCode ?? '';
        _order.text = banner.displayOrder.toString();
        _active = banner.isActive;
        _imageUrl = banner.imageUrl;
        _logoUrl = banner.logoUrl;
      });
    } catch (e) {
      _message('دریافت بنر ناموفق بود: $e');
    }
  }

  @override
  void dispose() {
    _title.dispose(); _subtitle.dispose(); _promoTitle.dispose(); _discountCode.dispose(); _order.dispose();
    super.dispose();
  }

  void _message(String value) {
    if (mounted) {
      final safeMessage = AppErrorMessage.forDisplay(
        value,
        fallback: 'عملیات بنر با مشکل روبه‌رو شد. اطلاعات را بررسی و دوباره تلاش کنید.',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(safeMessage)),
      );
    }
  }

  Future<void> _pickImage({required bool logo}) async {
    try {
      final picked = await UploadService.pickImageFromGallery();
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) throw Exception('فایل تصویر خالی است.');
      if (bytes.length > 12 * 1024 * 1024) throw Exception('حجم هر تصویر نباید از ۱۲ مگابایت بیشتر باشد.');
      setState(() {
        if (logo) { _logo = picked; _logoBytes = bytes; }
        else { _image = picked; _imageBytes = bytes; }
      });
    } catch (e) {
      _message('انتخاب تصویر ناموفق بود: $e');
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<BannersProvider>();
    setState(() => _saving = true);
    try {
      var imageUrl = _imageUrl ?? '';
      var logoUrl = _logoUrl ?? '';
      if (_image != null) imageUrl = await UploadService.uploadImage(file: _image!, folderName: 'banners', bucketName: 'banners');
      if (_logo != null) logoUrl = await UploadService.uploadImage(file: _logo!, folderName: 'logos', bucketName: 'banners');
      final data = <String, dynamic>{
        'title': _title.text.trim(),
        'subtitle': _subtitle.text.trim(),
        'promo_title': _promoTitle.text.trim(),
        'discount_code': _discountCode.text.trim().isEmpty ? null : _discountCode.text.trim().toUpperCase(),
        'logo_url': logoUrl,
        'sort_order': int.parse(_order.text.trim()),
        'is_active': _active,
        'image_url': imageUrl,
      };
      final ok = _editing ? await provider.updateBanner(widget.bannerId!, data) : await provider.createBanner(data);
      if (!ok) throw Exception(provider.error ?? 'ذخیره بنر انجام نشد.');
      await provider.fetchBanners();
      if (!mounted) return;
      _message(_editing ? 'بنر ویرایش شد.' : 'بنر اضافه شد.');
      Navigator.of(context).pop();
    } catch (e) {
      _message('ذخیره بنر ناموفق بود: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _nonNegativeInt(String? value) {
    final n = int.tryParse((value ?? '').trim());
    return n == null || n < 0 ? 'عدد صحیح نامنفی وارد کنید.' : null;
  }

  Widget _imagePickerCard({required bool logo}) {
    final bytes = logo ? _logoBytes : _imageBytes;
    final url = logo ? _logoUrl : _imageUrl;
    final selected = logo ? _logo : _image;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      OutlinedButton.icon(onPressed: _saving ? null : () => _pickImage(logo: logo), icon: Icon(logo ? Icons.verified_outlined : Icons.image_outlined), label: Text(selected?.name ?? (logo ? (url?.isNotEmpty == true ? 'لوگوی فعلی موجود است؛ برای جایگزینی انتخاب کنید' : 'انتخاب لوگوی بنر (اختیاری)') : (url?.isNotEmpty == true ? 'تصویر بنر موجود است؛ برای جایگزینی انتخاب کنید' : 'انتخاب تصویر اصلی بنر')))),
      if (bytes != null) Padding(padding: const EdgeInsets.only(top: 10), child: Align(alignment: Alignment.centerRight, child: Image.memory(bytes, height: logo ? 110 : 190, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Text('پیش‌نمایش تصویر ناموفق بود.'))))
      else if (url?.isNotEmpty == true) Padding(padding: const EdgeInsets.only(top: 10), child: Align(alignment: Alignment.centerRight, child: Image.network(url!, height: logo ? 90 : 170, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Text('تصویر قبلی قابل نمایش نیست.')))),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_editing ? 'ویرایش بنر' : 'افزودن بنر')),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: Form(key: _formKey, child: ListView(padding: const EdgeInsets.all(20), children: [
      TextFormField(controller: _title, decoration: const InputDecoration(labelText: 'عنوان اصلی بنر *', border: OutlineInputBorder()), validator: (v) => v == null || v.trim().isEmpty ? 'عنوان اصلی را وارد کنید.' : null),
      const SizedBox(height: 14),
      TextFormField(controller: _subtitle, decoration: const InputDecoration(labelText: 'عنوان کوچک / زیرعنوان', border: OutlineInputBorder())),
      const SizedBox(height: 14),
      TextFormField(controller: _promoTitle, decoration: const InputDecoration(labelText: 'عنوان تخفیف جمعی', hintText: 'مثلاً تخفیف ویژه آخر هفته', border: OutlineInputBorder())),
      const SizedBox(height: 14),
      TextFormField(controller: _discountCode, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'کد تخفیف (اختیاری)', border: OutlineInputBorder())),
      const SizedBox(height: 14),
      TextFormField(controller: _order, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ترتیب نمایش', border: OutlineInputBorder()), validator: _nonNegativeInt),
      const SizedBox(height: 18),
      Text('تصویر اصلی بنر', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      _imagePickerCard(logo: false),
      const SizedBox(height: 18),
      Text('لوگوی روی بنر', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      _imagePickerCard(logo: true),
      const SizedBox(height: 12),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: _saving ? null : (v) => setState(() => _active = v), title: const Text('فعال برای نمایش در اپ رستوران')),
      const SizedBox(height: 20),
      FilledButton.icon(onPressed: _saving ? null : _submit, icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined), label: Text(_saving ? 'در حال ذخیره…' : 'ذخیره بنر')),
    ])))),
  );
}
