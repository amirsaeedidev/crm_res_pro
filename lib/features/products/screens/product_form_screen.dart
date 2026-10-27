import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/services/upload_service.dart';
import '../../../core/utils/app_error_message.dart';
import '../../../models/product_model.dart';
import '../../../providers/categories_provider.dart';
import '../../../providers/products_provider.dart';
import '../../../repositories/products_repository.dart';

class ProductFormScreen extends StatefulWidget {
  final String? productId;
  const ProductFormScreen({super.key, this.productId});
  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _description = TextEditingController();
  final _aboutDish = TextEditingController();
  final _labels = TextEditingController();
  final _discountPercent = TextEditingController(text: '10');
  XFile? _image;
  Uint8List? _imageBytes;
  String? _imageUrl;
  String? _categoryId;
  bool _popular = false;
  bool _active = true;
  bool _discountEnabled = false;
  bool _saving = false;
  bool _loadingProduct = false;
  bool get _editing => widget.productId != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final categoriesProvider = context.read<CategoriesProvider>();
    final productsProvider = context.read<ProductsProvider>();
    final productsRepository = context.read<ProductsRepository>();
    await categoriesProvider.fetchCategories();
    if (!mounted || !_editing) return;
    setState(() => _loadingProduct = true);
    try {
      ProductModel? product = productsProvider.getProductById(widget.productId!);
      product ??= await productsRepository.getProductById(widget.productId!);
      if (!mounted) return;
      _name.text = product.name;
      _price.text = product.price.toStringAsFixed(0);
      _description.text = product.description;
      _aboutDish.text = product.aboutDish;
      _labels.text = product.labels.join(', ');
      _discountEnabled = product.discountPercent > 0;
      _discountPercent.text = product.discountPercent.toStringAsFixed(product.discountPercent % 1 == 0 ? 0 : 2);
      _imageUrl = product.imageUrl;
      _categoryId = product.categoryId;
      _popular = product.isPopular;
      _active = product.status == 'active';
      setState(() {});
    } catch (e) {
      if (mounted) _message(AppErrorMessage.from(e, fallback: 'دریافت اطلاعات محصول ناموفق بود. دوباره تلاش کنید.'));
    } finally {
      if (mounted) setState(() => _loadingProduct = false);
    }
  }

  @override
  void dispose() {
    _name.dispose(); _price.dispose(); _description.dispose(); _aboutDish.dispose(); _labels.dispose(); _discountPercent.dispose();
    super.dispose();
  }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _pickImage() async {
    try {
      final picked = await UploadService.pickImageFromGallery();
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) throw Exception('فایل انتخاب‌شده خالی است.');
      if (bytes.length > 12 * 1024 * 1024) throw Exception('حجم تصویر باید کمتر از ۱۲ مگابایت باشد.');
      setState(() { _image = picked; _imageBytes = bytes; });
    } catch (e) {
      _message(AppErrorMessage.forDisplay('انتخاب تصویر ناموفق بود: $e', fallback: 'انتخاب تصویر ناموفق بود. فرمت و اندازه فایل را بررسی کنید.'));
    }
  }

  String? _validatePrice(String? value) {
    final n = int.tryParse((value ?? '').trim());
    if (n == null || n <= 0) return 'قیمت باید عدد صحیح بزرگ‌تر از صفر باشد.';
    return null;
  }

  String? _validatePercent(String? value) {
    if (!_discountEnabled) return null;
    final n = double.tryParse((value ?? '').trim());
    if (n == null || n <= 0 || n > 100) return 'درصد تخفیف باید بیشتر از صفر و حداکثر ۱۰۰ باشد.';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<ProductsProvider>();
    setState(() => _saving = true);
    try {
      var imageUrl = _imageUrl ?? '';
      if (_image != null) imageUrl = await UploadService.uploadImage(file: _image!, folderName: 'products', bucketName: 'products');
      final percentage = _discountEnabled ? double.parse(_discountPercent.text.trim()) : 0.0;
      final labels = _labels.text.split(RegExp(r'[,،\n]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
      final data = <String, dynamic>{
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        'about_dish': _aboutDish.text.trim(),
        'labels': labels,
        'discount_percent': percentage,
        'price': int.parse(_price.text.trim()),
        'image_url': imageUrl,
        'category_id': _categoryId,
        'is_popular': _popular,
        'is_active': _active,
      };
      final ok = _editing ? await provider.updateProduct(widget.productId!, data) : await provider.createProduct(data);
      if (!ok) throw Exception(provider.error ?? 'ذخیره محصول انجام نشد.');
      await provider.fetchProducts();
      if (!mounted) return;
      _message(_editing ? 'محصول ویرایش شد.' : 'محصول اضافه شد.');
      Navigator.of(context).pop();
    } catch (e) {
      _message(AppErrorMessage.from(e, fallback: 'ذخیره محصول ناموفق بود. اطلاعات واردشده و اتصال را بررسی کنید.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_editing ? 'ویرایش محصول' : 'افزودن محصول')),
    body: _loadingProduct ? const Center(child: CircularProgressIndicator()) : Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Form(key: _formKey, child: ListView(padding: const EdgeInsets.all(20), children: [
        TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'نام محصول *', border: OutlineInputBorder()), validator: (v) => v == null || v.trim().isEmpty ? 'نام محصول را وارد کنید.' : null),
        const SizedBox(height: 14),
        TextFormField(controller: _price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'قیمت پایه (تومان) *', border: OutlineInputBorder()), validator: _validatePrice),
        const SizedBox(height: 14),
        Consumer<CategoriesProvider>(builder: (context, provider, _) => DropdownButtonFormField<String?>(initialValue: _categoryId, decoration: const InputDecoration(labelText: 'دسته‌بندی (اختیاری)', border: OutlineInputBorder()), items: [const DropdownMenuItem<String?>(value: null, child: Text('بدون دسته‌بندی')), ...provider.categories.map((cat) => DropdownMenuItem<String?>(value: cat.id, child: Text(cat.name)))], onChanged: provider.isLoading || _saving ? null : (value) => setState(() => _categoryId = value))),
        const SizedBox(height: 14),
        TextFormField(controller: _description, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'توضیحات عمومی', border: OutlineInputBorder())),
        const SizedBox(height: 14),
        TextFormField(controller: _aboutDish, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'درباره این غذا', hintText: 'مواد اولیه، روش آماده‌سازی، حساسیت غذایی و ...', border: OutlineInputBorder())),
        const SizedBox(height: 14),
        TextFormField(controller: _labels, decoration: const InputDecoration(labelText: 'لیبل‌ها', hintText: 'پرطرفدار، تند، گیاهی، جدید', helperText: 'لیبل‌ها را با ویرگول جدا کنید.', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: _discountEnabled, onChanged: _saving ? null : (v) => setState(() => _discountEnabled = v), title: const Text('اعمال تخفیف روی محصول'), subtitle: const Text('قیمت تخفیف‌خورده در سفارش هم از سمت دیتابیس محاسبه می‌شود.')),
        if (_discountEnabled) Padding(padding: const EdgeInsets.only(bottom: 12), child: TextFormField(controller: _discountPercent, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'درصد تخفیف', suffixText: '%', border: OutlineInputBorder()), validator: _validatePercent)),
        if (_discountEnabled && double.tryParse(_discountPercent.text) != null && double.tryParse(_price.text) != null)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('قیمت بعد از تخفیف: ${(double.parse(_price.text) * (100 - double.parse(_discountPercent.text)) / 100).round()} تومان')),
        OutlinedButton.icon(onPressed: _saving ? null : _pickImage, icon: const Icon(Icons.image_outlined), label: Text(_image?.name ?? (_imageUrl == null || _imageUrl!.isEmpty ? 'انتخاب تصویر محصول (اختیاری)' : 'تصویر ذخیره‌شده موجود است؛ برای جایگزینی انتخاب کنید'))),
        if (_imageBytes != null) Padding(padding: const EdgeInsets.only(top: 12), child: Image.memory(_imageBytes!, height: 180, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Text('پیش‌نمایش تصویر ناموفق بود.')))
        else if (_imageUrl != null && _imageUrl!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Image.network(_imageUrl!, height: 180, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Text('تصویر ذخیره‌شده قابل نمایش نیست.'))),
        const SizedBox(height: 8),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: _saving ? null : (v) => setState(() => _active = v), title: const Text('محصول فعال باشد'), subtitle: const Text('محصول غیرفعال برای کاربران عمومی نمایش داده نمی‌شود.')),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: _popular, onChanged: _saving ? null : (v) => setState(() => _popular = v), title: const Text('محصول پرطرفدار / محبوب')),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _saving ? null : _submit, icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined), label: Text(_saving ? 'در حال ذخیره…' : 'ذخیره محصول')),
      ])),
    )),
  );
}
