
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/upload_service.dart';
import '../../../core/utils/app_error_message.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../shared/dialogs/delete_dialog.dart';

class FileManagerScreen extends StatefulWidget {
  const FileManagerScreen({super.key});

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  static const _buckets = <String>['products', 'categories', 'banners'];
  String _selectedBucket = 'products';
  bool _isUploading = false;
  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _files = [];

  String _bucketLabel(String bucket) {
    switch (bucket) {
      case 'products':
        return 'تصاویر محصولات';
      case 'categories':
        return 'تصاویر دسته‌بندی‌ها';
      case 'banners':
        return 'تصاویر بنرها';
      default:
        return 'فایل‌های دیگر';
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFiles());
  }

  Future<void> _loadFiles() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final storage = SupabaseService.storage;
      final results = <Map<String, dynamic>>[];
      for (final bucket in _buckets) {
        final rootEntries = await storage.from(bucket).list();
        for (final entry in rootEntries) {
          final metadata = entry.metadata;
          final isFolder = entry.id == null && metadata == null;
          if (isFolder) {
            final children = await storage.from(bucket).list(path: entry.name);
            for (final child in children) {
              if (child.id == null && child.metadata == null) continue;
              final path = '${entry.name}/${child.name}';
              results.add(_toFile(bucket, path, child));
            }
          } else {
            results.add(_toFile(bucket, entry.name, entry));
          }
        }
      }
      results.sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
      if (mounted) setState(() => _files = results);
    } on StorageException catch (e) {
      if (mounted) setState(() => _error = AppErrorMessage.from(e, fallback: 'دریافت فهرست فایل‌ها ناموفق بود. اتصال و سطح دسترسی را بررسی کنید.'));
    } catch (e) {
      if (mounted) setState(() => _error = 'خطا در دریافت فایل‌ها: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _toFile(String bucket, String path, dynamic entry) {
    final metadata = entry.metadata;
    final size = metadata is Map ? (metadata['size'] ?? metadata['contentLength']) : null;
    final created = entry.createdAt?.toString() ?? entry.updatedAt?.toString() ?? '';
    final url = SupabaseService.storage.from(bucket).getPublicUrl(path);
    final ext = path.split('.').last.toLowerCase();
    return {
      'bucket': bucket,
      'path': path,
      'name': path.split('/').last,
      'url': url,
      'size': size is num ? size.toInt() : int.tryParse('$size'),
      'created_at': created,
      'is_image': const {'png','jpg','jpeg','webp','gif','avif'}.contains(ext),
    };
  }

  String _formatSize(dynamic raw) {
    if (raw is! num || raw <= 0) return 'حجم نامشخص';
    final bytes = raw.toDouble();
    if (bytes < 1024) return '${bytes.toInt()} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _pickAndUploadFile() async {
    final file = await UploadService.pickFile();
    if (file == null || !mounted) return;
    final extension = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : '';
    if (!const {'png','jpg','jpeg','webp','gif','avif'}.contains(extension)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('برای باکت‌های عمومی فقط فایل تصویری مجاز است.')));
      return;
    }
    setState(() => _isUploading = true);
    try {
      final url = await UploadService.uploadFile(
        file: file,
        folderName: 'uploads',
        bucketName: _selectedBucket,
      );
      if (url.isEmpty) throw Exception('بارگذاری تصویر انجام نشد؛ دسترسی بارگذاری فایل را بررسی کنید.');
      await _loadFiles();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تصویر با موفقیت ذخیره شد.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('آپلود ناموفق بود: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _deleteFile(Map<String, dynamic> file) async {
    try {
      await SupabaseService.storage.from(file['bucket'] as String).remove([file['path'] as String]);
      if (!mounted) return;
      await _loadFiles();
      if (!mounted || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فایل با موفقیت حذف شد.')));
    } on StorageException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppErrorMessage.from(e, fallback: 'حذف فایل ناموفق بود. لطفاً دوباره تلاش کنید.'))));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حذف ناموفق بود: $e')));
    }
  }

  void _showImagePreview(Map<String, dynamic> file) {
    showDialog<void>(context: context, builder: (dialogContext) => Dialog(
      child: Padding(padding: const EdgeInsets.all(AppSizes.md), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Align(alignment: Alignment.centerRight, child: IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close))),
        ConstrainedBox(constraints: const BoxConstraints(maxHeight: 500), child: Image.network(file['url'] as String, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Text('نمایش تصویر امکان‌پذیر نیست.'))),
        const SizedBox(height: AppSizes.sm),
        Text(_bucketLabel((file['bucket'] ?? '').toString())),
      ])),
    ));
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSizes.md),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('مدیریت فایل‌ها', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: AppColors.getPrimaryText(context), fontWeight: FontWeight.bold))),
        const SizedBox(width: AppSizes.sm),
        DropdownButton<String>(value: _selectedBucket, items: _buckets.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(), onChanged: (v) { if (v != null) setState(() => _selectedBucket = v); }),
        const SizedBox(width: AppSizes.sm),
        AppButton(label: _isUploading ? 'در حال آپلود...' : 'آپلود تصویر', icon: Icons.cloud_upload_outlined, isLoading: _isUploading, onPressed: _isUploading ? null : _pickAndUploadFile, width: 170),
      ]),
      const SizedBox(height: AppSizes.md),
      Text('نمایش فایل‌های تصاویر محصولات، دسته‌بندی‌ها و بنرها', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: AppSizes.md),
      if (_error != null) AppCard(child: Column(children: [Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 8), FilledButton(onPressed: _loadFiles, child: const Text('تلاش مجدد'))])),
      if (_isLoading) const Expanded(child: Center(child: CircularProgressIndicator()))
      else if (_files.isEmpty && _error == null) const Expanded(child: Center(child: Text('در باکت‌های قابل مشاهده فایلی پیدا نشد.')))
      else Expanded(child: RefreshIndicator(onRefresh: _loadFiles, child: GridView.builder(
        itemCount: _files.length,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 240, childAspectRatio: .78, crossAxisSpacing: AppSizes.md, mainAxisSpacing: AppSizes.md),
        itemBuilder: (context, index) {
          final file = _files[index];
          final isImage = file['is_image'] == true;
          return AppCard(padding: EdgeInsets.zero, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: Container(color: AppColors.getBackground(context), child: isImage
              ? Image.network(file['url'] as String, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, size: 42))
              : const Icon(Icons.insert_drive_file_outlined, size: 42))),
            Padding(padding: const EdgeInsets.all(AppSizes.sm), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(file['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('${_bucketLabel((file['bucket'] ?? '').toString())} • ${_formatSize(file['size'])}', style: Theme.of(context).textTheme.bodySmall),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                if (isImage) IconButton(tooltip: 'نمایش', onPressed: () => _showImagePreview(file), icon: const Icon(Icons.visibility_outlined, color: AppColors.info)),
                IconButton(tooltip: 'حذف', onPressed: () => DeleteDialog.show(context: context, title: 'حذف فایل', message: 'آیا فایل ${file['name']} از بخش ${_bucketLabel((file['bucket'] ?? '').toString())} حذف شود؟', onDelete: () => _deleteFile(file)), icon: const Icon(Icons.delete_outline, color: AppColors.error)),
              ]),
            ])),
          ]));
        },
      ))),
    ]),
  );
}
