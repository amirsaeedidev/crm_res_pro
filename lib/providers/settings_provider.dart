import 'package:flutter/material.dart';

import '../core/services/logger_service.dart';
import '../core/utils/app_error_message.dart';
import '../core/services/storage_service.dart';
import '../repositories/settings_repository.dart';

class SettingsProvider extends ChangeNotifier {
  final SettingsRepository _repository;

  Color _primaryColor = const Color(0xFF2563EB);
  Color _secondaryColor = const Color(0xFF0EA5E9);
  double? _minDeliveryAmount;
  double? _fixedDeliveryFee;
  String _companyName = '';
  String _companyPhone = '';
  String _companyAddress = '';
  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _error;

  SettingsProvider(this._repository) {
    _loadSettings();
  }

  Color get primaryColor => _primaryColor;
  Color get secondaryColor => _secondaryColor;
  double? get minDeliveryAmount => _minDeliveryAmount;
  double? get fixedDeliveryFee => _fixedDeliveryFee;
  String get companyName => _companyName;
  String get companyPhone => _companyPhone;
  String get companyAddress => _companyAddress;
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  String? get error => _error;

  Future<void> reload() => _loadSettings();

  Future<void> _loadSettings() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      // Local values are used only while loading/when no remote value exists;
      // editable business settings always come from the shared Supabase row.
      final localPrimary = StorageService.getInt('primary_color');
      final localSecondary = StorageService.getInt('secondary_color');
      if (localPrimary != null) _primaryColor = Color(localPrimary);
      if (localSecondary != null) _secondaryColor = Color(localSecondary);

      final settings = await _repository.getSettings();
      if (settings.isNotEmpty) {
        _companyName = (settings['company_name'] ?? '').toString();
        _companyPhone = (settings['company_phone'] ?? '').toString();
        _companyAddress = (settings['company_address'] ?? '').toString();
        _minDeliveryAmount = (settings['min_delivery_amount'] as num?)?.toDouble();
        _fixedDeliveryFee = (settings['fixed_delivery_fee'] as num?)?.toDouble();
        final primary = (settings['primary_color'] as num?)?.toInt();
        final secondary = (settings['secondary_color'] as num?)?.toInt();
        if (primary != null) {
          _primaryColor = Color(primary);
          await StorageService.setInt('primary_color', primary);
        }
        if (secondary != null) {
          _secondaryColor = Color(secondary);
          await StorageService.setInt('secondary_color', secondary);
        }
      } else {
        _error = 'تنظیمات فروشگاه در پایگاه داده پیدا نشد. ابتدا ساختار پایگاه داده را به‌روزرسانی کنید.';
      }
    } catch (e, st) {
      _error = _friendlyError(e);
      LoggerService.error('Load settings failed', error: e, stackTrace: st);
    } finally {
      _isLoading = false;
      _hasLoaded = true;
      notifyListeners();
    }
  }

  Future<bool> setPrimaryColor(Color color) => _setColors(color, _secondaryColor);

  Future<bool> setSecondaryColor(Color color) => _setColors(_primaryColor, color);

  Future<bool> _setColors(Color primary, Color secondary) async {
    _error = null;
    _isLoading = true;
    notifyListeners();
    try {
      await _repository.updateColors(
        primaryColor: primary.toARGB32(),
        secondaryColor: secondary.toARGB32(),
      );
      _primaryColor = primary;
      _secondaryColor = secondary;
      await StorageService.setInt('primary_color', primary.toARGB32());
      await StorageService.setInt('secondary_color', secondary.toARGB32());
      return true;
    } catch (e, st) {
      _error = _friendlyError(e);
      LoggerService.error('Save brand colors failed', error: e, stackTrace: st);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> saveSettings(Map<String, dynamic> data) async {
    final minimum = _readAmount(data['min_delivery_amount'], 'حداقل مبلغ سفارش');
    final fee = _readAmount(data['fixed_delivery_fee'], 'هزینه ارسال');
    if (minimum == null || fee == null) return false;

    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final row = await _repository.saveSettings(
        companyName: (data['company_name'] ?? '').toString(),
        companyPhone: (data['company_phone'] ?? '').toString(),
        companyAddress: (data['company_address'] ?? '').toString(),
        minDeliveryAmount: minimum,
        fixedDeliveryFee: fee,
      );
      _companyName = (row['company_name'] ?? '').toString();
      _companyPhone = (row['company_phone'] ?? '').toString();
      _companyAddress = (row['company_address'] ?? '').toString();
      _minDeliveryAmount = (row['min_delivery_amount'] as num?)?.toDouble() ?? minimum;
      _fixedDeliveryFee = (row['fixed_delivery_fee'] as num?)?.toDouble() ?? fee;
      return true;
    } catch (e, st) {
      _error = _friendlyError(e);
      LoggerService.error('Save settings failed', error: e, stackTrace: st);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  double? _readAmount(dynamic value, String label) {
    final amount = value is num ? value.toDouble() : double.tryParse('$value');
    if (amount == null || !amount.isFinite || amount < 0) {
      _error = '$label باید عدد معتبر و نامنفی باشد.';
      notifyListeners();
      return null;
    }
    return amount;
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('PGRST205') ||
        text.contains('42P01') ||
        text.contains('restaurant_settings')) {
      return 'ساختار تنظیمات فروشگاه در پایگاه داده آماده نیست. ابتدا به‌روزرسانی ساختار پایگاه داده را اجرا کنید.';
    }
    if (text.contains('42501') ||
        text.toLowerCase().contains('permission')) {
      return 'اجازه دسترسی به تنظیمات داده نشد. با حساب مدیر فعال وارد شوید و سطح دسترسی را بررسی کنید.';
    }
    return AppErrorMessage.from(
      error,
      fallback: 'ذخیره یا دریافت تنظیمات ناموفق بود. اتصال و دسترسی حساب مدیر را بررسی کنید.',
    );
  }
}
