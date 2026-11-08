import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../constants/app_sizes.dart';
import '../theme/app_breakpoints.dart';
import 'app_sidebar.dart';
import 'app_topbar.dart';
import '../../providers/navigation_provider.dart';
import '../services/realtime_service.dart';

class MainLayout extends StatefulWidget {
  final Widget child;
  final String currentRoute;

  const MainLayout({
    super.key,
    required this.child,
    required this.currentRoute,
  });

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  StreamSubscription<String>? _realtimeErrorSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<NavigationProvider>().updateNavigation(widget.currentRoute);
      }
    });
    _realtimeErrorSubscription = RealtimeService.connectionErrors.listen((message) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ));
      });
    });
  }

  @override
  void didUpdateWidget(covariant MainLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentRoute != widget.currentRoute) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<NavigationProvider>().updateNavigation(widget.currentRoute);
        }
      });
    }
  }

  @override
  void dispose() {
    _realtimeErrorSubscription?.cancel();
    super.dispose();
  }

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
      case '/notifications':
        return 'مدیریت اعلان‌ها';
      case '/notification-inbox':
        return 'صندوق اعلان‌ها';
      case '/activity-logs':
        return 'ثبت فعالیت‌ها';
      default:
        return 'داشبورد';
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= AppBreakpoints.laptop; // 1024px

    // Intercept back inside the ShellRoute navigator. Pushed forms/details
    // still pop normally; at the section root we restore the previous section.
    return PopScope<Object?>(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final previousRoute = context.read<NavigationProvider>().goBack();
        if (previousRoute != null) {
          context.go(previousRoute);
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
      drawer: isDesktop
          ? null
          : Drawer(
              width: AppSizes.sidebarWidth,
              child: const AppSidebar(drawerMode: true),
            ),
      body: SafeArea(
        top: true,
        bottom: false,
        child: Row(
          children: [
            // نوار کناری در نمایشگرهای بزرگ
            if (isDesktop) const AppSidebar(),

            // محتوای اصلی پنل
            Expanded(
              child: Column(
                children: [
                  AppTopbar(
                    title: _getPageTitle(widget.currentRoute),
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
      ),
      ),
    );
  }
}