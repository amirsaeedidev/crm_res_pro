import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/constants/app_routes.dart';
import '../core/widgets/main_layout.dart';
import '../core/widgets/admin_route_guard.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/dashboard/screens/dashboard_screen.dart';
import '../features/categories/screens/categories_list_screen.dart';
import '../features/categories/screens/category_form_screen.dart';
import '../features/products/screens/products_list_screen.dart';
import '../features/products/screens/product_form_screen.dart';
import '../features/products/screens/product_details_screen.dart';
import '../features/banners/screens/banners_list_screen.dart';
import '../features/banners/screens/banner_form_screen.dart';
import '../features/discounts/screens/discounts_list_screen.dart';
import '../features/discounts/screens/discount_form_screen.dart';
import '../features/customers/screens/customers_list_screen.dart';
import '../features/customers/screens/customer_details_screen.dart';
import '../features/orders/screens/orders_list_screen.dart';
import '../features/orders/screens/order_details_screen.dart';
import '../features/reports/screens/reports_screen.dart';
import '../features/reports/screens/expenses_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/reservations/screens/reservations_list_screen.dart';
import '../features/tables/screens/tables_grid_screen.dart';
import '../features/file_manager/screens/file_manager_screen.dart';
import '../features/tickets/screens/tickets_list_screen.dart';
import '../features/tickets/screens/ticket_details_screen.dart';
import '../features/loyalty/screens/loyalty_screen.dart';
import '../features/sms/screens/sms_center_screen.dart';
import '../features/inventory/screens/inventory_screen.dart';
import '../features/wallet/screens/customer_wallets_screen.dart';

class AppRouter {
  static final _rootNavigatorKey = GlobalKey<NavigatorState>();

  // Fixed: Changed from a getter to a static final field to prevent
  // the router from being recreated on every UI rebuild (e.g., Theme change),
  // which caused the app to reset to the initial location.
  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.login,
    navigatorKey: _rootNavigatorKey,
    routes: [
      // Login Route (Outside Shell)
      GoRoute(
        path: AppRoutes.login,
        name: AppRoutes.login,
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const NoTransitionPage(
          child: LoginRouteGuard(child: LoginScreen()),
        ),
      ),

      // Routes inside the Main Layout (Sidebar + Topbar)
      ShellRoute(
        builder: (context, state, child) => AdminRouteGuard(child: MainLayout(child: child)),
        routes: [
          GoRoute(path: AppRoutes.dashboard, name: AppRoutes.dashboard, pageBuilder: (context, state) => const NoTransitionPage(child: DashboardScreen())),
          GoRoute(path: AppRoutes.orders, name: AppRoutes.orders, pageBuilder: (context, state) => const NoTransitionPage(child: OrdersListScreen())),
          GoRoute(path: AppRoutes.products, name: AppRoutes.products, pageBuilder: (context, state) => const NoTransitionPage(child: ProductsListScreen())),
          GoRoute(path: AppRoutes.customers, name: AppRoutes.customers, pageBuilder: (context, state) => const NoTransitionPage(child: CustomersListScreen())),
          GoRoute(path: AppRoutes.categories, name: AppRoutes.categories, pageBuilder: (context, state) => const NoTransitionPage(child: CategoriesListScreen())),
          GoRoute(path: '/banners', name: 'banners', pageBuilder: (context, state) => const NoTransitionPage(child: BannersListScreen())),
          GoRoute(path: '/discounts', name: 'discounts', pageBuilder: (context, state) => const NoTransitionPage(child: DiscountsListScreen())),
          GoRoute(path: AppRoutes.reservations, name: AppRoutes.reservations, pageBuilder: (context, state) => const NoTransitionPage(child: ReservationsListScreen())),
          GoRoute(path: AppRoutes.tables, name: AppRoutes.tables, pageBuilder: (context, state) => const NoTransitionPage(child: TablesGridScreen())),
          GoRoute(path: AppRoutes.reports, name: AppRoutes.reports, pageBuilder: (context, state) => const NoTransitionPage(child: ReportsScreen())),
          GoRoute(path: '/expenses', name: 'expenses', pageBuilder: (context, state) => const NoTransitionPage(child: ExpensesScreen())),
          GoRoute(path: AppRoutes.settings, name: AppRoutes.settings, pageBuilder: (context, state) => const NoTransitionPage(child: SettingsScreen())),
          GoRoute(path: AppRoutes.tickets, name: AppRoutes.tickets, pageBuilder: (context, state) => const NoTransitionPage(child: TicketsListScreen())),
          GoRoute(path: AppRoutes.files, name: AppRoutes.files, pageBuilder: (context, state) => const NoTransitionPage(child: FileManagerScreen())),
          GoRoute(path: AppRoutes.loyalty, name: AppRoutes.loyalty, pageBuilder: (context, state) => const NoTransitionPage(child: LoyaltyScreen())),
          GoRoute(path: AppRoutes.sms, name: AppRoutes.sms, pageBuilder: (context, state) => const NoTransitionPage(child: SmsCenterScreen())),
          GoRoute(path: AppRoutes.inventory, name: AppRoutes.inventory, pageBuilder: (context, state) => const NoTransitionPage(child: InventoryScreen())),
          GoRoute(path: AppRoutes.wallets, name: AppRoutes.wallets, pageBuilder: (context, state) => const NoTransitionPage(child: CustomerWalletsScreen())),
        ],
      ),
      
      // Full Screen Routes
      GoRoute(path: '/categories/add', name: 'category_add', parentNavigatorKey: _rootNavigatorKey, pageBuilder: (context, state) => const MaterialPage(child: AdminRouteGuard(child: CategoryFormScreen()))),
      GoRoute(
        path: '/categories/edit/:id',
        name: 'category_edit',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) {
          final categoryId = state.pathParameters['id']!; 
          return MaterialPage(child: AdminRouteGuard(child: CategoryFormScreen(categoryId: categoryId)));
        },
      ),

      GoRoute(path: '/products/add', name: 'product_add', parentNavigatorKey: _rootNavigatorKey, pageBuilder: (context, state) => const MaterialPage(child: AdminRouteGuard(child: ProductFormScreen()))),
      GoRoute(
        path: '/products/edit/:id',
        name: 'product_edit',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) {
          final productId = state.pathParameters['id']!;
          return MaterialPage(child: AdminRouteGuard(child: ProductFormScreen(productId: productId)));
        },
      ),
      GoRoute(
        path: '/products/details/:id',
        name: 'product_details',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) {
          final productId = state.pathParameters['id']!;
          return MaterialPage(child: AdminRouteGuard(child: ProductDetailsScreen(productId: productId)));
        },
      ),

      GoRoute(path: '/banners/add', name: 'banner_add', parentNavigatorKey: _rootNavigatorKey, pageBuilder: (context, state) => const MaterialPage(child: AdminRouteGuard(child: BannerFormScreen()))),
      GoRoute(
        path: '/banners/edit/:id',
        name: 'banner_edit',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) {
          final bannerId = state.pathParameters['id']!;
          return MaterialPage(child: AdminRouteGuard(child: BannerFormScreen(bannerId: bannerId)));
        },
      ),

      GoRoute(path: '/discounts/add', name: 'discount_add', parentNavigatorKey: _rootNavigatorKey, pageBuilder: (context, state) => const MaterialPage(child: AdminRouteGuard(child: DiscountFormScreen()))),
      GoRoute(
        path: '/discounts/edit/:id',
        name: 'discount_edit',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) {
          final discountId = state.pathParameters['id']!;
          return MaterialPage(child: AdminRouteGuard(child: DiscountFormScreen(discountId: discountId)));
        },
      ),

      GoRoute(
        path: '/customers/details/:id',
        name: 'customer_details',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) {
          final customerId = state.pathParameters['id']!;
          return MaterialPage(child: AdminRouteGuard(child: CustomerDetailsScreen(customerId: customerId)));
        },
      ),
      GoRoute(
        path: '/tickets/:id',
        name: 'ticket_details',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => MaterialPage(child: AdminRouteGuard(child: TicketDetailsScreen(ticketId: state.pathParameters['id']!))),
      ),

      GoRoute(
        path: '/orders/details/:id',
        name: 'order_details',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) {
          final orderId = state.pathParameters['id']!;
          return MaterialPage(child: AdminRouteGuard(child: OrderDetailsScreen(orderId: orderId)));
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(body: Center(child: Text('Page not found (404)'))),
  );
}