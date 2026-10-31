import 'package:flutter/material.dart';
import '../core/services/logger_service.dart';
import '../core/utils/app_error_message.dart';
import '../models/table_model.dart';
import '../repositories/tables_repository.dart';

class TablesProvider extends ChangeNotifier {
  final TablesRepository _repository;
  TablesProvider(this._repository);

  // State
  bool _isLoading = false;
  bool _isUpdating = false;
  String? _error;
  List<TableModel> _tables = [];

  // Getters
  bool get isLoading => _isLoading;
  bool get isUpdating => _isUpdating;
  String? get error => _error;
  List<TableModel> get tables => _tables;

  Future<void> fetchTables({DateTime? reservationDate}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _tables = await _repository.getTables(reservationDate: reservationDate);
    } catch (e, st) {
      LoggerService.error('Fetch tables failed in provider', error: e, stackTrace: st);
      _error = AppErrorMessage.from(e, fallback: 'دریافت فهرست میزها ناموفق بود. دوباره تلاش کنید.');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }


  Future<bool> createTable({required int tableNumber, required int capacity, bool isActive = true}) async {
    _isUpdating = true; _error = null; notifyListeners();
    try {
      await _repository.createTable(tableNumber: tableNumber, capacity: capacity, isActive: isActive);
      _tables = await _repository.getTables();
      return true;
    } catch (e, st) {
      LoggerService.error('Create table failed in provider', error: e, stackTrace: st);
      _error = AppErrorMessage.from(e, fallback: 'ثبت میز ناموفق بود. اطلاعات را بررسی و دوباره تلاش کنید.'); return false;
    } finally { _isUpdating = false; notifyListeners(); }
  }

  Future<bool> updateTable({required String id, required int tableNumber, required int capacity, required bool isActive}) async {
    _isUpdating = true; _error = null; notifyListeners();
    try {
      await _repository.updateTable(id, tableNumber: tableNumber, capacity: capacity, isActive: isActive);
      _tables = await _repository.getTables();
      return true;
    } catch (e, st) {
      LoggerService.error('Update table failed in provider', error: e, stackTrace: st);
      _error = AppErrorMessage.from(e, fallback: 'ویرایش اطلاعات میز ناموفق بود. دوباره تلاش کنید.'); return false;
    } finally { _isUpdating = false; notifyListeners(); }
  }

  Future<bool> setTableActive(String id, bool isActive) async {
    _isUpdating = true; _error = null; notifyListeners();
    try {
      await _repository.updateTable(id, isActive: isActive);
      _tables = await _repository.getTables();
      return true;
    } catch (e, st) {
      LoggerService.error('Change table active state failed in provider', error: e, stackTrace: st);
      _error = AppErrorMessage.from(e, fallback: 'تغییر وضعیت فعال بودن میز ناموفق بود. دوباره تلاش کنید.'); return false;
    } finally { _isUpdating = false; notifyListeners(); }
  }

  Future<bool> markTableAsFree(String tableId) async {
    _isUpdating = true;
    notifyListeners();

    try {
      await _repository.updateTableStatus(tableId, 'free', null);
      
      _tables = await _repository.getTables();
      notifyListeners();
      return true;
    } catch (e, st) {
      LoggerService.error('Mark table as free failed', error: e, stackTrace: st);
      _error = AppErrorMessage.from(e, fallback: 'آزاد کردن میز ناموفق بود. ابتدا وضعیت سفارش فعال را بررسی کنید.');
      return false;
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }

  Future<bool> assignOrderToTable(String tableId, String orderId) async {
    _isUpdating = true;
    notifyListeners();

    try {
      await _repository.updateTableStatus(tableId, 'occupied', orderId);
      
      _tables = await _repository.getTables();
      notifyListeners();
      return true;
    } catch (e, st) {
      LoggerService.error('Assign order to table failed', error: e, stackTrace: st);
      _error = AppErrorMessage.from(e, fallback: 'اتصال سفارش به میز ناموفق بود. دوباره تلاش کنید.');
      return false;
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }
}