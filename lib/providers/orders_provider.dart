import 'package:flutter/material.dart';
import '../core/utils/app_error_message.dart';
import '../models/order_model.dart';
import '../core/services/logger_service.dart';
import '../repositories/orders_repository.dart';

class OrdersProvider extends ChangeNotifier {
  final OrdersRepository _repository;
  OrdersProvider(this._repository);

  // List State
  bool _isLoading = false;
  String? _error;
  List<OrderModel> _orders = [];
  int _currentPage = 1;
  int _totalPages = 1;
  String _searchQuery = '';
  String _statusFilter = 'all';
  final int _pageSize = 15;
  int _listRequestVersion = 0;
  int _detailsRequestVersion = 0;
  int _searchVersion = 0;
  bool _disposed = false;

  // Details State
  OrderModel? _selectedOrder;
  bool _isLoadingDetails = false;
  String? _detailsError;
  bool _isUpdatingStatus = false;

  // Getters
  bool get isLoading => _isLoading;
  bool get isLoadingDetails => _isLoadingDetails;
  bool get isUpdatingStatus => _isUpdatingStatus;
  String? get error => _error;
  String? get detailsError => _detailsError;
  List<OrderModel> get orders => _orders;
  OrderModel? get selectedOrder => _selectedOrder;
  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  String get searchQuery => _searchQuery;
  String get statusFilter => _statusFilter;

  Future<void> fetchOrders() async {
    if (_disposed) return;
    final requestVersion = ++_listRequestVersion;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final orders = await _repository.getOrders(
        page: _currentPage,
        pageSize: _pageSize,
        searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
        status: _statusFilter == 'all' ? null : _statusFilter,
      );
      if (_disposed || requestVersion != _listRequestVersion) return;
      _orders = orders;
      _totalPages = _orders.length == _pageSize ? _currentPage + 1 : _currentPage;
    } catch (e) {
      if (_disposed || requestVersion != _listRequestVersion) return;
      _error = AppErrorMessage.from(e);
    } finally {
      if (!_disposed && requestVersion == _listRequestVersion) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> fetchOrderDetails(String id) async {
    if (_disposed) return;
    final requestVersion = ++_detailsRequestVersion;
    _isLoadingDetails = true;
    _detailsError = null;
    _selectedOrder = null;
    notifyListeners();

    try {
      final order = await _repository.getOrderById(id);
      if (_disposed || requestVersion != _detailsRequestVersion) return;
      _selectedOrder = order;
    } catch (e) {
      if (_disposed || requestVersion != _detailsRequestVersion) return;
      _detailsError = AppErrorMessage.from(e, fallback: 'دریافت جزئیات سفارش ناموفق بود. دوباره تلاش کنید.');
    } finally {
      if (!_disposed && requestVersion == _detailsRequestVersion) {
        _isLoadingDetails = false;
        notifyListeners();
      }
    }
  }

  /// Search waits briefly for typing to pause and prevents older requests from
  /// replacing results for a newer query.
  Future<void> setSearchQuery(String query) async {
    final normalized = query.trim();
    if (normalized == _searchQuery) return;
    _searchQuery = normalized;
    _currentPage = 1;
    final searchVersion = ++_searchVersion;
    ++_listRequestVersion;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (_disposed || searchVersion != _searchVersion) return;
    await fetchOrders();
  }

  Future<void> setStatusFilter(String status) async {
    ++_searchVersion;
    _statusFilter = status;
    _currentPage = 1;
    await fetchOrders();
  }

  Future<void> changePage(int page) async {
    if (page < 1 || page > _totalPages) return;
    ++_searchVersion;
    _currentPage = page;
    await fetchOrders();
  }

  Future<bool> updateOrderStatus(String orderId, String newStatus) async {
    _isUpdatingStatus = true;
    notifyListeners();

    try {
      await _repository.updateOrderStatus(orderId, newStatus);
      
      // Update local state
      final index = _orders.indexWhere((o) => o.id == orderId);
      if (index != -1) {
        _orders[index] = _orders[index].copyWith(status: newStatus);
      }
      if (_selectedOrder?.id == orderId) {
        _selectedOrder = _selectedOrder!.copyWith(status: newStatus);
      }
      return true;
    } catch (e) {
      _detailsError = AppErrorMessage.from(e, fallback: 'دریافت جزئیات سفارش ناموفق بود. دوباره تلاش کنید.');
      return false;
    } finally {
      _isUpdatingStatus = false;
      notifyListeners();
    }
  }

  Future<bool> updateEstimatedDeliveryTime(String orderId, int minutes) async {
    if (minutes < 1) {
      _detailsError = 'زمان آماده‌سازی باید بیشتر از صفر دقیقه باشد.';
      notifyListeners();
      return false;
    }
    try {
      await _repository.updateOrderMetadata(orderId, {'estimated_ready_minutes': minutes});
      if (_selectedOrder?.id == orderId) {
        _selectedOrder = _selectedOrder!.copyWith(estimatedReadyMinutes: minutes);
      }
      _detailsError = null;
      notifyListeners();
      return true;
    } catch (e, st) {
      LoggerService.error('Update estimated ready time failed', error: e, stackTrace: st);
      _detailsError = AppErrorMessage.from(e, fallback: 'دریافت جزئیات سفارش ناموفق بود. دوباره تلاش کنید.');
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateOrderAdminNote(String orderId, String note) async {
    try {
      final value = note.trim();
      await _repository.updateOrderMetadata(orderId, {'admin_note': value.isEmpty ? null : value});
      if (_selectedOrder?.id == orderId) {
        _selectedOrder = _selectedOrder!.copyWith(adminNote: value);
      }
      _detailsError = null;
      notifyListeners();
      return true;
    } catch (e, st) {
      LoggerService.error('Update order admin note failed', error: e, stackTrace: st);
      _detailsError = AppErrorMessage.from(e, fallback: 'دریافت جزئیات سفارش ناموفق بود. دوباره تلاش کنید.');
      notifyListeners();
      return false;
    }
  }


  @override
  void dispose() {
    _disposed = true;
    ++_searchVersion;
    ++_listRequestVersion;
    ++_detailsRequestVersion;
    super.dispose();
  }

}