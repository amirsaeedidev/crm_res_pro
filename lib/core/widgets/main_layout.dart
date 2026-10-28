import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_sizes.dart';
import '../theme/app_breakpoints.dart';
import 'app_sidebar.dart';
import 'app_topbar.dart';
import '../../providers/navigation_provider.dart';

class MainLayout extends StatefulWidget {
  final Widget child;

  const MainLayout({super.key, required this.child});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Translate the current route to a Persian app-bar title.
  String _getPageTitle(String route) {
    switch (route) {
      case '/dashboard':
        return 'داشبورد';
      case '/orders':
        return 'سفارشات';
      case '/products':
        return 'محصولات';
      case '/customers':
        return 'مشتریان';
      case '/categories':
        return 'دسته‌بندی‌ها';
      case '/banners':
        return 'بنرها';
      case '/discounts':
        return 'تخفیف‌ها';
      case '/reports':
        return 'گزارش‌ها';
      case '/settings':
        return 'تنظیمات';
      case '/reservations':
        return 'رزروها';
      case '/tables':
        return 'میزها';
      case '/tickets':
        return 'تیکت‌ها';
      case '/files':
        return 'مدیریت فایل‌ها';
      case '/loyalty':
        return 'باشگاه مشتریان';
      case '/sms':
        return 'مرکز پیامک';
      case '/inventory':
        return 'انبارداری و مواد اولیه';
      case '/wallets':
        return 'کیف پول مالی مشتریان';
      default:
        return 'داشبورد';
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= AppBreakpoints.laptop; // 1024px
    final navProvider = context.watch<NavigationProvider>();

    // Directionality is now applied globally in app.dart
    return Scaffold(
      key: _scaffoldKey,
      drawer: isDesktop
          ? null
          : Drawer(
              width: AppSizes.sidebarWidth,
              child: const AppSidebar(),
            ),
      body: Row(
        children: [
          // Permanent Sidebar for Desktop (Will appear on the Right due to RTL)
          if (isDesktop) const AppSidebar(),

          // Main Content Area
          Expanded(
            child: Column(
              children: [
                AppTopbar(
                  // استفاده از متد تبدیل مسیر به فارسی
                  title: _getPageTitle(navProvider.currentRoute),
                  onMenuTap: () {
                    if (!isDesktop) {
                      _scaffoldKey.currentState?.openDrawer();
                    }
                  },
                ),
                Expanded(
                  child: Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: widget.child,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}