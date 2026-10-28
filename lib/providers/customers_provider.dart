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

  Future<void> fetchCustomers() async {
    if (_disposed) return;
    final requestVersion = ++_requestVersion;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final customers = await _repository.getCustomers(
        page: _page,
        pageSize: _pageSize,
        searchQuery: _search.isEmpty ? null : _search,
        statusFilter: _statusFilter,
        marketingOptInFilter: _marketingFilter == 'all' ? null : _marketingFilter == 'opted_in',
      );
      if (_disposed || requestVersion != _requestVersion) return;
      _customers = customers;
      _totalPages = _customers.length == _pageSize ? _page + 1 : _page;
    } catch (e) {
      if (_disposed || requestVersion != _requestVersion) return;
      _error = e.toString();
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
      _error = e.toString();
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
