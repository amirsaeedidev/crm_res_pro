import 'package:flutter/material.dart';

import '../core/services/logger_service.dart';
import '../core/utils/app_error_message.dart';
import '../models/statistics_model.dart';
import '../models/order_model.dart';
import '../repositories/dashboard_repository.dart';

class DashboardProvider extends ChangeNotifier {
  final DashboardRepository _repository;

  DashboardProvider(this._repository);

  bool _isLoading = false;
  bool _disposed = false;
  int _requestVersion = 0;

  String? _error;
  String? _recentOrdersError;
  StatisticsModel? _statistics;
  List<OrderModel> _recentOrders = const [];

  DateTime? _startAt;
  DateTime? _endAt;
  String _orderSource = 'all';
  String _paymentMode = 'all';

  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get recentOrdersError => _recentOrdersError;
  StatisticsModel? get statistics => _statistics;
  List<OrderModel> get recentOrders => List.unmodifiable(_recentOrders);

  DateTime? get startAt => _startAt;
  DateTime? get endAt => _endAt;
  String get orderSource => _orderSource;
  String get paymentMode => _paymentMode;

  /// Fetch filtered statistics and the latest orders. Older responses are
  /// ignored when the user changes filters before a request finishes.
  Future<void> fetchDashboardData({
    DateTime? startAt,
    DateTime? endAt,
    String orderSource = 'all',
    String paymentMode = 'all',
  }) async {
    if (_disposed) return;

    final requestVersion = ++_requestVersion;
    _startAt = startAt;
    _endAt = endAt;
    _orderSource = orderSource;
    _paymentMode = paymentMode;

    _isLoading = true;
    _error = null;
    _recentOrdersError = null;
    _notifyIfAlive();

    await Future.wait<void>([
      _fetchStatistics(requestVersion),
      _fetchRecentOrders(requestVersion),
    ]);

    if (!_disposed && requestVersion == _requestVersion) {
      _isLoading = false;
      _notifyIfAlive();
    }
  }

  Future<void> _fetchStatistics(int requestVersion) async {
    try {
      final result = await _repository.getStatistics(
        startAt: _startAt,
        endAt: _endAt,
        orderSource: _orderSource,
        paymentMode: _paymentMode,
      );

      if (_disposed || requestVersion != _requestVersion) return;
      _statistics = result;
      _error = null;
      LoggerService.info('Filtered dashboard overview loaded');
    } catch (error, stackTrace) {
      if (_disposed || requestVersion != _requestVersion) return;
      _error = _readableError(error);
      LoggerService.error(
        'Failed to fetch dashboard overview',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _fetchRecentOrders(int requestVersion) async {
    try {
      final result = await _repository.getRecentOrders(limit: 5);
      if (_disposed || requestVersion != _requestVersion) return;
      _recentOrders = result;
      _recentOrdersError = null;
    } catch (error, stackTrace) {
      if (_disposed || requestVersion != _requestVersion) return;
      _recentOrdersError = _readableError(error);
      LoggerService.error(
        'Failed to fetch recent dashboard orders',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  String _readableError(Object error) {
    return AppErrorMessage.from(
      error,
      fallback: 'دریافت اطلاعات داشبورد ناموفق بود. لطفاً دوباره تلاش کنید.',
    );
  }

  void _notifyIfAlive() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _requestVersion++;
    super.dispose();
  }
}
