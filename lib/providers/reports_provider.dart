import 'package:flutter/material.dart';
import '../core/services/logger_service.dart';
import '../core/utils/app_error_message.dart';
import '../models/report_model.dart';
import '../repositories/reports_repository.dart';

class ReportsProvider extends ChangeNotifier {
  final ReportsRepository _repository;
  ReportsProvider(this._repository);

  // State
  bool _isLoading = false;
  String? _error;
  ReportModel? _salesReport;
  ReportModel? _topProductsReport;
  ReportModel? _customerDistributionReport;
  ReportModel? _financialReport;
  ReportModel? _inventoryReport;

  // Getters
  bool get isLoading => _isLoading;
  String? get error => _error;
  ReportModel? get salesReport => _salesReport;
  ReportModel? get topProductsReport => _topProductsReport;
  ReportModel? get customerDistributionReport => _customerDistributionReport;
  ReportModel? get financialReport => _financialReport;
  ReportModel? get inventoryReport => _inventoryReport;

  Future<void> fetchSalesReport({required DateTime startDate, required DateTime endDate}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _salesReport = await _repository.getSalesReport(startDate: startDate, endDate: endDate);
    } catch (e, st) {
      LoggerService.error('Fetch sales report failed in provider', error: e, stackTrace: st);
      _error = AppErrorMessage.from(e, fallback: 'دریافت گزارش فروش ناموفق بود. دوباره تلاش کنید.');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchTopProductsReport({int limit = 10}) async {
    try {
      _topProductsReport = await _repository.getTopProductsReport(limit: limit);
      notifyListeners();
    } catch (e, st) {
      LoggerService.error('Fetch top products report failed in provider', error: e, stackTrace: st);
      _error = AppErrorMessage.from(e, fallback: 'دریافت فهرست محصولات پرفروش ناموفق بود. دوباره تلاش کنید.');
      notifyListeners();
    }
  }

  Future<void> fetchCustomerDistributionReport() async {
    try {
      _customerDistributionReport = await _repository.getCustomerDistributionReport();
      notifyListeners();
    } catch (e, st) {
      LoggerService.error('Fetch customer distribution report failed in provider', error: e, stackTrace: st);
      _error = AppErrorMessage.from(e, fallback: 'دریافت گزارش مشتریان ناموفق بود. دوباره تلاش کنید.');
      notifyListeners();
    }
  }

  Future<void> fetchFinancialReport({required DateTime startDate, required DateTime endDate}) async {
    try {
      _financialReport = await _repository.getFinancialReport(startDate: startDate, endDate: endDate);
      notifyListeners();
    } catch (e, st) {
      LoggerService.error('Fetch financial report failed in provider', error: e, stackTrace: st);
      _error = AppErrorMessage.from(e, fallback: 'دریافت گزارش مالی ناموفق بود. دوباره تلاش کنید.');
      notifyListeners();
    }
  }

  Future<void> fetchInventoryReport({required DateTime startDate, required DateTime endDate}) async {
    try {
      _inventoryReport = await _repository.getInventoryReport(startDate: startDate, endDate: endDate);
      notifyListeners();
    } catch (e, st) {
      LoggerService.error('Fetch inventory report failed in provider', error: e, stackTrace: st);
      _error = AppErrorMessage.from(e, fallback: 'دریافت گزارش انبار ناموفق بود. دوباره تلاش کنید.');
      notifyListeners();
    }
  }

}
