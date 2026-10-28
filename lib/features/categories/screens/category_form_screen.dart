import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/services/upload_service.dart';
import '../../../providers/categories_provider.dart';
import '../../../repositories/categories_repository.dart';

class CategoryFormScreen extends StatefulWidget {
  final String? categoryId;
  const CategoryFormScreen({super.key, this.categoryId});
  @override
  State<CategoryFormScreen> createState() => _CategoryFormScreenState();
}

class _CategoryFormScreenState extends State<CategoryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _sortOrder = TextEditingController(text: '0');
  final _loyaltyPoints = TextEditingController(text: '0');
  XFile? _image;
  Uint8List? _imageBytes;
  String? _existingImageUrl;
  bool _active = true;
  bool _saving = false;
  bool get _editing => widget.categoryId != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCategory());
  }

  Future<void> _loadCategory() async {
    if (!mounted) return;
    final provider = context.read<CategoriesProvider>();
    final repository = context.read<CategoriesRepository>();
    if (provider.categories.isEmpty) await provider.fetchCategories();
    if (!mounted || !_editing) return;
    try {
      final category = provider.getCategoryById(widget.categoryId!) ??
          await repository.getCategoryById(widget.categoryId!);
      if (!mounted) return;
      setState(() {
        _name.text = category.name;
        _sortOrder.text = category.displayOrder.toString();
        _loyaltyPoints.text = category.loyaltyPointsPerItem.toString();
        _active = category.isActive;
        _existingImageUrl = category.imageUrl;
      });
    } catch (e) {
      if (mounted) _message('دریافت دسته‌بندی ناموفق بود: $e');
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _sortOrder.dispose();
    _loyaltyPoints.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
      _message('انتخاب تصویر ناموفق بود: $e');
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<CategoriesProvider>();
    setState(() => _saving = true);
    try {
      var imageUrl = _existingImageUrl ?? '';
      if (_image != null) {
        imageUrl = await UploadService.uploadImage(file: _image!, folderName: 'categories', bucketName: 'categories');
      }
      final data = <String, dynamic>{
        'name': _name.text.trim(),
        'sort_order': int.parse(_sortOrder.text.trim()),
        'loyalty_points_per_item': int.parse(_loyaltyPoints.text.trim()),
        'is_active': _active,
        'image_url': imageUrl,
      };
      final ok = _editing
          ? await provider.updateCategory(widget.categoryId!, data)
          : await provider.createCategory(data);
      if (!ok) throw Exception(provider.error ?? 'ذخیره دسته‌بندی انجام نشد.');
      await provider.fetchCategories();
      if (!mounted) return;
      _message(_editing ? 'دسته‌بندی ویرایش شد.' : 'دسته‌بندی اضافه شد.');
      Navigator.of(context).pop();
    } catch (e) {
      _message('ذخیره دسته‌بندی ناموفق بود: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _nonNegativeInt(String? value) {
    final n = int.tryParse((value ?? '').trim());
    if (n == null || n < 0) return 'عدد صحیح نامنفی وارد کنید.';
    return null;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_editing ? 'ویرایش دسته‌بندی' : 'افزودن دسته‌بندی')),
    body: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: Form(key: _formKey, child: ListView(padding: const EdgeInsets.all(20), children: [
        TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'نام دسته‌بندی *', border: OutlineInputBorder()), validator: (v) => v == null || v.trim().isEmpty ? 'نام را وارد کنید.' : null),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: TextFormField(controller: _sortOrder, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ترتیب نمایش', border: OutlineInputBorder()), validator: _nonNegativeInt)),
          const SizedBox(width: 12),
          Expanded(child: TextFormField(controller: _loyaltyPoints, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'امتیاز وفاداری برای هر آیتم', border: OutlineInputBorder()), validator: _nonNegativeInt)),
        ]),
        const SizedBox(height: 14),
        OutlinedButton.icon(onPressed: _saving ? null : _pickImage, icon: const Icon(Icons.image_outlined), label: Text(_image?.name ?? (_existingImageUrl == null || _existingImageUrl!.isEmpty ? 'انتخاب تصویر دسته‌بندی (اختیاری)' : 'تصویر ذخیره‌شده موجود است؛ برای جایگزینی انتخاب کنید'))),
        if (_imageBytes != null) Padding(padding: const EdgeInsets.only(top: 12), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_imageBytes!, height: 160, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Text('نمایش پیش‌نمایش تصویر ناموفق بود.'))))
        else if (_existingImageUrl != null && _existingImageUrl!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Image.network(_existingImageUrl!, height: 150, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Text('تصویر قبلی قابل نمایش نیست.'))),
        const SizedBox(height: 8),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('فعال برای نمایش در اپ رستوران'), value: _active, onChanged: _saving ? null : (v) => setState(() => _active = v)),
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: _saving ? null : _submit, icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined), label: Text(_saving ? 'در حال ذخیره…' : 'ذخیره')),
      ])),
    )),
  );
}
