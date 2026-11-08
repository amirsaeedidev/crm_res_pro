import 'package:flutter/material.dart';
import '../core/constants/app_routes.dart';

class NavigationProvider extends ChangeNotifier {
  String _currentRoute = AppRoutes.dashboard;
  int _selectedIndex = 0;
  final List<String> _routeHistory = [];

  String get currentRoute => _currentRoute;
  int get selectedIndex => _selectedIndex;

  void updateNavigation(String route) {
    if (_currentRoute == route) return;

    _routeHistory.add(_currentRoute);
    if (_routeHistory.length > 50) _routeHistory.removeAt(0);

    _currentRoute = route;
    _selectedIndex = _getIndexByRoute(route);
    notifyListeners();
  }

  /// Moves the provider state to the previous route before the router changes.
  /// This prevents the route observer from adding the popped route back to history.
  String? goBack() {
    if (_routeHistory.isEmpty) return null;

    final previousRoute = _routeHistory.removeLast();
    _currentRoute = previousRoute;
    _selectedIndex = _getIndexByRoute(previousRoute);
    notifyListeners();
    return previousRoute;
  }

  void clearHistory() {
    _routeHistory.clear();
  }

  void updateIndex(int index) {
    if (_selectedIndex == index) return;

    final route = _getRouteByIndex(index);
    if (route == _currentRoute) return;

    _routeHistory.add(_currentRoute);
    if (_routeHistory.length > 50) _routeHistory.removeAt(0);

    _selectedIndex = index;
    _currentRoute = route;
    notifyListeners();
  }

  int _getIndexByRoute(String route) {
    switch (route) {
      case AppRoutes.dashboard:
        return 0;
      case AppRoutes.orders:
        return 1;
      case AppRoutes.products:
        return 2;
      case AppRoutes.customers:
        return 3;
      case AppRoutes.categories:
        return 4;
      case AppRoutes.reports:
        return 5;
      case AppRoutes.settings:
        return 6;
      case AppRoutes.tables:
        return 7;
      case AppRoutes.reservations:
        return 8;
      case AppRoutes.loyalty:
        return 13;
      case AppRoutes.sms:
        return 14;
      case AppRoutes.inventory:
        return 15;
      case AppRoutes.wallets:
        return 16;
      case AppRoutes.notifications:
        return 17;
      case AppRoutes.activityLogs:
        return 18;
      case '/banners':
        return 9;
      case '/discounts':
        return 10;
      case AppRoutes.tickets:
        return 11;
      case AppRoutes.files:
        return 12;
      default:
        return 0;
    }
  }

  String _getRouteByIndex(int index) {
    switch (index) {
      case 0:
        return AppRoutes.dashboard;
      case 1:
        return AppRoutes.orders;
      case 2:
        return AppRoutes.products;
      case 3:
        return AppRoutes.customers;
      case 4:
        return AppRoutes.categories;
      case 5:
        return AppRoutes.reports;
      case 6:
        return AppRoutes.settings;
      case 7:
        return AppRoutes.tables;
      case 8:
        return AppRoutes.reservations;
      case 9:
        return '/banners';
      case 10:
        return '/discounts';
      case 11:
        return AppRoutes.tickets;
      case 12:
        return AppRoutes.files;
      case 13:
        return AppRoutes.loyalty;
      case 14:
        return AppRoutes.sms;
      case 15:
        return AppRoutes.inventory;
      case 16:
        return AppRoutes.wallets;
      case 17:
        return AppRoutes.notifications;
      case 18:
        return AppRoutes.activityLogs;
      default:
        return AppRoutes.dashboard;
    }
  }
}
