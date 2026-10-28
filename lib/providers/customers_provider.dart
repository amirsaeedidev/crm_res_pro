import '../core/utils/app_error_message.dart';
import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import '../repositories/customers_repository.dart';

class CustomersProvider extends ChangeNotifier {
  final CustomersRepository _repository;
  CustomersProvider(this._repository);

  bool _isLoading = false;
  String? _error;
  List<UserModel> _customers = [];
  int _page = 1;
  int _totalPages = 1;
  String _search = '';
  String _statusFilter = 'all';
  String _marketingFilter = 'all';
  int? _minPurchases;
  int? _maxPurchases;
  double? _minSpend;
  double? _maxSpend;
  String _lastVisitFilter = 'all';
  String _sortBy = 'recent';
  int _totalCount = 0;
  static const int _pageSize = 20;
  int _requestVersion = 0;
  int _searchVersion = 0;
  bool _disposed = false;

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<UserModel> get customers => List.unmodifiable(_customers);
  int get currentPage => _page;
  int get totalPages => _totalPages;
  String get searchQuery => _search;
  String get statusFilter => _statusFilter;
  String get marketingFilter => _marketingFilter;
  int get totalCount => _totalCount;
  int? get minPurchases => _minPurchases;
  int? get maxPurchases => _maxPurchases;
  double? get minSpend => _minSpend;
  double? get maxSpend => _maxSpend;
  String get lastVisitFilter => _lastVisitFilter;
  String get sortBy => _sortBy;

  Future<void> fetchCustomers() async {
    if (_disposed) return;
    final requestVersion = ++_requestVersion;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _repository.getCustomersWithPurchaseMetrics(
        page: _page,
        pageSize: _pageSize,
        searchQuery: _search.isEmpty ? null : _search,
        statusFilter: _statusFilter,
        marketingOptInFilter: _marketingFilter == 'all' ? null : _marketingFilter == 'opted_in',
        minOrders: _minPurchases,
        maxOrders: _maxPurchases,
        minSpend: _minSpend,
        maxSpend: _maxSpend,
        lastVisitFilter: _lastVisitFilter,
        sortBy: _sortBy,
      );
      if (_disposed || requestVersion != _requestVersion) return;
      _customers = result.customers;
      _totalCount = result.totalCount;
      _totalPages = _totalCount == 0 ? 1 : (_totalCount + _pageSize - 1) ~/ _pageSize;
      if (_page > _totalPages) _page = _totalPages;
    } catch (e) {
      if (_disposed || requestVersion != _requestVersion) return;
      _error = AppErrorMessage.from(e);
    } finally {
      if (!_disposed && requestVersion == _requestVersion) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Debounce search input to reduce unnecessary network requests.
  Future<void> setSearchQuery(String value) async {
    final normalized = value.trim();
    if (normalized == _search) return;
    _search = normalized;
    _page = 1;
    final searchVersion = ++_searchVersion;
    ++_requestVersion;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (_disposed || searchVersion != _searchVersion) return;
    await fetchCustomers();
  }

  Future<void> setStatusFilter(String value) async {
    ++_searchVersion;
    _statusFilter = value;
    _page = 1;
    await fetchCustomers();
  }

  Future<void> setMarketingFilter(String value) async {
    ++_searchVersion;
    _marketingFilter = value;
    _page = 1;
    await fetchCustomers();
  }


  Future<void> setPurchaseFilters({
    int? minPurchases,
    int? maxPurchases,
    double? minSpend,
    double? maxSpend,
    required String lastVisitFilter,
    required String sortBy,
  }) async {
    if (minPurchases != null && maxPurchases != null && minPurchases > maxPurchases) {
      _error = 'حداقل تعداد خرید نمی‌تواند از حداکثر بیشتر باشد.';
      notifyListeners();
      return;
    }
    if (minSpend != null && maxSpend != null && minSpend > maxSpend) {
      _error = 'حداقل مبلغ خرید نمی‌تواند از حداکثر بیشتر باشد.';
      notifyListeners();
      return;
    }
    _minPurchases = minPurchases;
    _maxPurchases = maxPurchases;
    _minSpend = minSpend;
    _maxSpend = maxSpend;
    _lastVisitFilter = lastVisitFilter;
    _sortBy = sortBy;
    _page = 1;
    await fetchCustomers();
  }

  Future<void> resetPurchaseFilters() async {
    _minPurchases = null;
    _maxPurchases = null;
    _minSpend = null;
    _maxSpend = null;
    _lastVisitFilter = 'all';
    _sortBy = 'recent';
    _page = 1;
    await fetchCustomers();
  }

  Future<void> changePage(int value) async {
    if (value < 1 || value > _totalPages) return;
    ++_searchVersion;
    _page = value;
    await fetchCustomers();
  }

  Future<bool> updateCustomerStatus(String id, String status) async {
    try {
      await _repository.updateCustomerStatus(id, status);
      final index = _customers.indexWhere((customer) => customer.id == id);
      if (index >= 0) _customers[index] = _customers[index].copyWith(status: status);
      notifyListeners();
      return true;
    } catch (e) {
      _error = AppErrorMessage.from(e);
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_searchVersion;
    ++_requestVersion;
    super.dispose();
  }
}
