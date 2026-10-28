import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/supabase_config.dart';
import 'logger_service.dart';
import 'supabase_service.dart';

/// Web-safe uploads for Flutter Web, Android, iOS and desktop.
/// Never depend on dart:io File or an XFile path: browser pickers often have no
/// local filesystem path and Image.file is not supported on Flutter Web.
class UploadService {
  UploadService._();

  static const _uuid = Uuid();
  static const int _maxImageBytes = 12 * 1024 * 1024;
  static const Set<String> _allowedExtensions = {'png', 'jpg', 'jpeg', 'webp', 'gif', 'avif'};

  static Future<XFile?> pickImageFromGallery() async {
    try {
      return await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    } catch (e, st) {
      LoggerService.error('Image selection failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  static Future<XFile?> pickImageFromCamera() async {
    try {
      return await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
    } catch (e, st) {
      LoggerService.error('Camera capture failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// File picker returns bytes so the same API works in a browser.
  static Future<PlatformFile?> pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.custom,
        allowedExtensions: _allowedExtensions.toList(),
      );
      if (result == null || result.files.isEmpty) return null;
      return result.files.single;
    } catch (e, st) {
      LoggerService.error('File selection failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  static Future<String> uploadImage({
    required XFile file,
    required String folderName,
    String? bucketName,
  }) async {
    final bytes = await file.readAsBytes();
    return _uploadBytes(
      bytes: bytes,
      originalName: file.name,
      folderName: folderName,
      bucketName: bucketName,
    );
  }

  static Future<String> uploadFile({
    required PlatformFile file,
    required String folderName,
    String? bucketName,
  }) async {
    final Uint8List? bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('مرورگر بایت‌های فایل را در اختیار برنامه نگذاشت. فایل را دوباره انتخاب کنید.');
    }
    return _uploadBytes(
      bytes: bytes,
      originalName: file.name,
      folderName: folderName,
      bucketName: bucketName,
    );
  }

  static Future<String> _uploadBytes({
    required Uint8List bytes,
    required String originalName,
    required String folderName,
    String? bucketName,
  }) async {
    if (bytes.isEmpty) throw const FormatException('فایل انتخاب‌شده خالی است.');
    if (bytes.length > _maxImageBytes) {
      throw const FormatException('حجم تصویر نباید بیشتر از ۱۲ مگابایت باشد.');
    }

    final cleanedName = originalName.trim().replaceAll('\\', '/').split('/').last;
    final dotIndex = cleanedName.lastIndexOf('.');
    if (dotIndex < 1 || dotIndex == cleanedName.length - 1) {
      throw const FormatException('فرمت تصویر مشخص نیست. فایل PNG، JPG یا WEBP انتخاب کنید.');
    }
    final extension = cleanedName.substring(dotIndex + 1).toLowerCase();
    if (!_allowedExtensions.contains(extension)) {
      throw const FormatException('فرمت مجاز: PNG، JPG، WEBP، GIF یا AVIF.');
    }

    final contentType = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'avif' => 'image/avif',
      _ => 'application/octet-stream',
    };
    final targetBucket = bucketName ?? SupabaseConfig.storageBucket;
    final safeFolder = folderName.replaceAll('..', '').replaceAll('\\', '/').replaceAll('/', '').trim();
    if (safeFolder.isEmpty) throw const FormatException('مسیر ذخیره‌سازی تصویر نامعتبر است.');
    final filePath = '$safeFolder/${_uuid.v4()}.$extension';

    try {
      await SupabaseService.storage.from(targetBucket).uploadBinary(
        filePath,
        bytes,
        fileOptions: FileOptions(
          cacheControl: '3600',
          contentType: contentType,
          upsert: false,
        ),
      );
      final publicUrl = SupabaseService.storage.from(targetBucket).getPublicUrl(filePath);
      LoggerService.info('Image uploaded to Storage bucket=$targetBucket path=$filePath bytes=${bytes.length}');
      return publicUrl;
    } on StorageException catch (e, st) {
      LoggerService.error('Storage upload failed for $targetBucket/$filePath', error: e, stackTrace: st);
      final reason = e.statusCode == '403'
          ? 'دسترسی آپلود در باکت $targetBucket رد شد. نشست مدیر و سیاست‌های Storage را بررسی کنید.'
          : e.statusCode == '413'
              ? 'حجم تصویر از حد مجاز Storage بیشتر است.'
              : 'Storage (${e.statusCode ?? 'بدون کد'}): ${e.message}';
      throw Exception(reason);
    } catch (e, st) {
      LoggerService.error('Upload failed for $targetBucket/$filePath', error: e, stackTrace: st);
      throw Exception('آپلود تصویر ناموفق بود: $e');
    }
  }

  static Future<bool> deleteFile({
    required String folderName,
    required String fileName,
    String? bucketName,
  }) async {
    try {
      final targetBucket = bucketName ?? SupabaseConfig.storageBucket;
      final path = '$folderName/$fileName';
      await SupabaseService.storage.from(targetBucket).remove([path]);
      LoggerService.info('File deleted from $targetBucket: $path');
      return true;
    } catch (e, st) {
      LoggerService.error('Delete Storage file failed', error: e, stackTrace: st);
      return false;
    }
  }
}
