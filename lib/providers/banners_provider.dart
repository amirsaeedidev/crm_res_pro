import 'package:flutter/material.dart';
import '../core/services/logger_service.dart';
import '../models/banner_model.dart';
import '../repositories/banners_repository.dart';

class BannersProvider extends ChangeNotifier {
  final BannersRepository _repository;
  BannersProvider(this._repository);

  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;
  List<BannerModel> _banners = [];
  int _currentPage = 1;
  int _totalPages = 1;
  String _searchQuery = '';
  final int _pageSize = 15;

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get error => _error;
  List<BannerModel> get banners => _banners;
  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  String get searchQuery => _searchQuery;

  Future<void> fetchBanners() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _banners = await _repository.getBanners(
        page: _currentPage,
        pageSize: _pageSize,
        searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
      );
      _totalPages = _banners.length == _pageSize ? _currentPage + 1 : _currentPage;
    } catch (e, st) {
      LoggerService.error('Fetch banners failed', error: e, stackTrace: st);
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setSearchQuery(String query) async {
    _searchQuery = query;
    _currentPage = 1;
    await fetchBanners();
  }

  Future<void> changePage(int page) async {
    if (page < 1 || page > _totalPages) return;
    _currentPage = page;
    await fetchBanners();
  }

  BannerModel? getBannerById(String id) {
    try {
      return _banners.firstWhere((b) => b.id == id);
    } catch (e) {
      return null;
    }
  }

  Future<bool> createBanner(Map<String, dynamic> data) async {
    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      final newBanner = await _repository.createBanner(data);
      _banners.insert(0, newBanner);
      notifyListeners();
      return true;
    } catch (e, st) {
      LoggerService.error('Create banner failed', error: e, stackTrace: st);
      _error = e.toString();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<bool> updateBanner(String id, Map<String, dynamic> data) async {
    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      final updatedBanner = await _repository.updateBanner(id, data);
      final index = _banners.indexWhere((b) => b.id == id);
      if (index != -1) {
        _banners[index] = updatedBanner;
      }
      notifyListeners();
      return true;
    } catch (e, st) {
      LoggerService.error('Update banner failed', error: e, stackTrace: st);
      _error = e.toString();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<bool> deleteBanner(String id) async {
    try {
      await _repository.deleteBanner(id);
      _banners.removeWhere((b) => b.id == id);
      notifyListeners();
      return true;
    } catch (e, st) {
      LoggerService.error('Delete banner failed', error: e, stackTrace: st);
      _error = e.toString();
      return false;
    }
  }

  Future<bool> toggleBannerStatus(String id, bool isActive) async {
    try {
      await _repository.updateBanner(id, {'is_active': isActive});
      final index = _banners.indexWhere((b) => b.id == id);
      if (index != -1) {
        _banners[index] = _banners[index].copyWith(isActive: isActive);
        notifyListeners();
      }
      return true;
    } catch (e, st) {
      LoggerService.error('Toggle banner status failed', error: e, stackTrace: st);
      _error = e.toString();
      return false;
    }
  }
}