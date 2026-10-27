import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/services/upload_service.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/utils/app_error_message.dart';
import '../../../core/widgets/app_card.dart';
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
      if (mounted) {
        _message(AppErrorMessage.from(
          e,
          fallback: 'دریافت اطلاعات دسته‌بندی ناموفق بود. دوباره تلاش کنید.',
        ));
      }
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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _pickImage() async {
    try {
      final picked = await UploadService.pickImageFromGallery();
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) throw Exception('فایل انتخاب‌شده خالی است.');
      if (bytes.length > 12 * 1024 * 1024) {
        throw Exception('حجم تصویر باید کمتر از ۱۲ مگابایت باشد.');
      }
      setState(() {
        _image = picked;
        _imageBytes = bytes;
      });
    } catch (e) {
      _message(AppErrorMessage.forDisplay(
        'انتخاب تصویر ناموفق بود: $e',
        fallback: 'انتخاب تصویر ناموفق بود. فرمت و اندازه فایل را بررسی کنید.',
      ));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<CategoriesProvider>();
    setState(() => _saving = true);
    try {
      var imageUrl = _existingImageUrl ?? '';
      if (_image != null) {
        imageUrl = await UploadService.uploadImage(
          file: _image!,
          folderName: 'categories',
          bucketName: 'categories',
        );
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
      _message(AppErrorMessage.from(
        e,
        fallback: 'ذخیره دسته‌بندی ناموفق بود. اطلاعات واردشده و اتصال را بررسی کنید.',
      ));
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
        appBar: AppBar(
          title: Text(_editing ? 'ویرایش دسته‌بندی' : 'افزودن دسته‌بندی'),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(AppSizes.lg),
                children: [
                  AppCard(
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.10),
                            borderRadius: AppRadius.mediumAll,
                          ),
                          child: const Icon(
                            Icons.category_outlined,
                            color: AppColors.primary,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: AppSizes.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _editing ? 'ویرایش دسته‌بندی' : 'دسته‌بندی جدید',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: AppSizes.xs),
                              Text(
                                'اطلاعات دسته‌بندی در پنل و اپ رستوران استفاده می‌شود.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                  color: AppColors.getSecondaryText(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSizes.md),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'اطلاعات اصلی',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: AppSizes.md),
                        TextFormField(
                          controller: _name,
                          decoration: const InputDecoration(
                            labelText: 'نام دسته‌بندی *',
                            prefixIcon: Icon(Icons.label_outline),
                          ),
                          textInputAction: TextInputAction.next,
                          validator: (value) => value == null || value.trim().isEmpty
                              ? 'نام را وارد کنید.'
                              : null,
                        ),
                        const SizedBox(height: AppSizes.md),
                        TextFormField(
                          controller: _sortOrder,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'ترتیب نمایش',
                            prefixIcon: Icon(Icons.sort),
                            helperText: 'عدد کمتر، جایگاه بالاتری دارد.',
                          ),
                          validator: _nonNegativeInt,
                        ),
                        const SizedBox(height: AppSizes.md),
                        TextFormField(
                          controller: _loyaltyPoints,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'امتیاز وفاداری برای هر آیتم',
                            prefixIcon: Icon(Icons.stars_outlined),
                          ),
                          validator: _nonNegativeInt,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSizes.md),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تصویر و نمایش',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: AppSizes.md),
                        Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(minHeight: 110),
                          padding: const EdgeInsets.all(AppSizes.sm),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme
                                .surfaceContainerHighest.withValues(alpha: 0.35),
                            borderRadius: AppRadius.largeAll,
                            border: Border.all(
                              color: AppColors.getBorder(context).withValues(alpha: 0.75),
                            ),
                          ),
                          child: _imageBytes != null
                              ? ClipRRect(
                                  borderRadius: AppRadius.mediumAll,
                                  child: Image.memory(
                                    _imageBytes!,
                                    height: 180,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, _, _) => const Center(
                                      child: Text('نمایش پیش‌نمایش تصویر ناموفق بود.'),
                                    ),
                                  ),
                                )
                              : (_existingImageUrl != null &&
                                      _existingImageUrl!.isNotEmpty)
                                  ? ClipRRect(
                                      borderRadius: AppRadius.mediumAll,
                                      child: Image.network(
                                        _existingImageUrl!,
                                        height: 180,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, _, _) => const Center(
                                          child: Text('تصویر قبلی قابل نمایش نیست.'),
                                        ),
                                      ),
                                    )
                                  : const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(AppSizes.lg),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.add_photo_alternate_outlined, size: 34),
                                            SizedBox(height: AppSizes.xs),
                                            Text('برای دسته‌بندی تصویر انتخاب کنید (اختیاری)'),
                                          ],
                                        ),
                                      ),
                                    ),
                        ),
                        const SizedBox(height: AppSizes.md),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _saving ? null : _pickImage,
                            icon: const Icon(Icons.image_outlined),
                            label: Text(
                              _image != null
                                  ? _image!.name
                                  : (_existingImageUrl == null ||
                                          _existingImageUrl!.isEmpty)
                                      ? 'انتخاب تصویر دسته‌بندی'
                                      : 'جایگزینی تصویر ذخیره‌شده',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSizes.sm),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: Icon(
                            _active
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: _active
                                ? AppColors.success
                                : AppColors.getSecondaryText(context),
                          ),
                          title: const Text('فعال برای نمایش در اپ رستوران'),
                          subtitle: Text(
                            _active
                                ? 'این دسته‌بندی برای مشتریان قابل مشاهده است.'
                                : 'این دسته‌بندی از اپ رستوران پنهان می‌شود.',
                          ),
                          value: _active,
                          onChanged: _saving
                              ? null
                              : (value) => setState(() => _active = value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSizes.lg),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _submit,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'در حال ذخیره…' : 'ذخیره دسته‌بندی'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
