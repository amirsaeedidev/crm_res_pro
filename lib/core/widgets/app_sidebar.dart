import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../constants/app_strings.dart';
import '../constants/app_routes.dart';
import '../theme/app_typography.dart';
import 'navigation_item.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/auth_provider.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final navProvider = context.watch<NavigationProvider>();
    final authProvider = context.watch<AuthProvider>();
    
    final user = authProvider.currentUser;
    final displayName = user != null 
        ? ((user.firstName != null && user.firstName!.isNotEmpty) 
            ? '${user.firstName} ${user.lastName ?? ''}'.trim() 
            : user.email)
        : 'مدیر';
    final displayEmail = user?.email ?? '—';

    return Container(
      width: AppSizes.sidebarWidth,
      color: AppColors.surfaceDark,
      child: Column(
        children: [
          // Logo Header
          Container(
            height: AppSizes.topBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.dashboard, color: AppColors.primary, size: AppSizes.iconLg),
                const SizedBox(width: AppSizes.sm),
                Text(
                  AppStrings.appName,
                  style: AppTypography.headlineMedium.copyWith(
                    color: AppColors.textPrimaryDark,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Divider(color: AppColors.borderDark, height: 1),
          
          // Menu Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                vertical: AppSizes.md,
                horizontal: AppSizes.sm,
              ),
              children: [
                NavigationItem(
                  icon: Icons.home_outlined,
                  label: AppStrings.dashboard,
                  isActive: navProvider.selectedIndex == 0,
                  onTap: () {
                    navProvider.updateIndex(0);
                    context.go(AppRoutes.dashboard);
                  },
                ),
                NavigationItem(
                  icon: Icons.shopping_bag_outlined,
                  label: AppStrings.orders,
                  isActive: navProvider.selectedIndex == 1,
                  onTap: () {
                    navProvider.updateIndex(1);
                    context.go(AppRoutes.orders);
                  },
                ),
                NavigationItem(
                  icon: Icons.inventory_2_outlined,
                  label: AppStrings.products,
                  isActive: navProvider.selectedIndex == 2,
                  onTap: () {
                    navProvider.updateIndex(2);
                    context.go(AppRoutes.products);
                  },
                ),
                NavigationItem(
                  icon: Icons.people_outline,
                  label: AppStrings.customers,
                  isActive: navProvider.selectedIndex == 3,
                  onTap: () {
                    navProvider.updateIndex(3);
                    context.go(AppRoutes.customers);
                  },
                ),
                NavigationItem(
                  icon: Icons.category_outlined,
                  label: AppStrings.categories,
                  isActive: navProvider.selectedIndex == 4,
                  onTap: () {
                    navProvider.updateIndex(4);
                    context.go(AppRoutes.categories);
                  },
                ),
                NavigationItem(
                  icon: Icons.analytics_outlined,
                  imageAssetPath: 'assets/images/dashboard_reports.webp',
                  label: AppStrings.reports,
                  isActive: navProvider.selectedIndex == 5,
                  onTap: () {
                    navProvider.updateIndex(5);
                    context.go(AppRoutes.reports);
                  },
                ),
                NavigationItem(
                  icon: Icons.table_restaurant_outlined,
                  label: 'میزها',
                  isActive: navProvider.selectedIndex == 7,
                  onTap: () {
                    navProvider.updateIndex(7);
                    context.go(AppRoutes.tables);
                  },
                ),
                NavigationItem(
                  icon: Icons.event_available_outlined,
                  label: 'رزروها',
                  isActive: navProvider.selectedIndex == 8,
                  onTap: () {
                    navProvider.updateIndex(8);
                    context.go(AppRoutes.reservations);
                  },
                ),
                NavigationItem(
                  icon: Icons.campaign_outlined,
                  label: 'بنرها',
                  isActive: navProvider.selectedIndex == 9,
                  onTap: () { navProvider.updateIndex(9); context.go('/banners'); },
                ),
                NavigationItem(
                  icon: Icons.discount_outlined,
                  label: 'تخفیف‌ها',
                  isActive: navProvider.selectedIndex == 10,
                  onTap: () { navProvider.updateIndex(10); context.go('/discounts'); },
                ),
                NavigationItem(
                  icon: Icons.support_agent_outlined,
                  label: 'تیکت‌ها',
                  isActive: navProvider.selectedIndex == 11,
                  onTap: () { navProvider.updateIndex(11); context.go(AppRoutes.tickets); },
                ),
                NavigationItem(
                  icon: Icons.folder_open_outlined,
                  label: 'مدیریت فایل‌ها',
                  isActive: navProvider.selectedIndex == 12,
                  onTap: () { navProvider.updateIndex(12); context.go(AppRoutes.files); },
                ),
                NavigationItem(
                  icon: Icons.loyalty_outlined,
                  label: 'باشگاه مشتریان',
                  isActive: navProvider.selectedIndex == 13,
                  onTap: () { navProvider.updateIndex(13); context.go(AppRoutes.loyalty); },
                ),
                NavigationItem(
                  icon: Icons.sms_outlined,
                  label: 'مرکز پیامک',
                  isActive: navProvider.selectedIndex == 14,
                  onTap: () { navProvider.updateIndex(14); context.go(AppRoutes.sms); },
                ),
                NavigationItem(
                  icon: Icons.warehouse_outlined,
                  label: 'انبارداری و مواد اولیه',
                  isActive: navProvider.selectedIndex == 15,
                  onTap: () { navProvider.updateIndex(15); context.go(AppRoutes.inventory); },
                ),
                NavigationItem(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'کیف پول مالی مشتریان',
                  isActive: navProvider.selectedIndex == 16,
                  onTap: () { navProvider.updateIndex(16); context.go(AppRoutes.wallets); },
                ),
                NavigationItem(
                  icon: Icons.settings_outlined,
                  label: AppStrings.settings,
                  isActive: navProvider.selectedIndex == 6,
                  onTap: () {
                    navProvider.updateIndex(6);
                    context.go(AppRoutes.settings);
                  },
                ),
              ],
            ),
          ),
          
          // Footer User Info
          Container(
            padding: const EdgeInsets.all(AppSizes.md),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.borderDark, width: 1)),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: AppColors.primary,
                  child: Icon(Icons.person, color: Colors.white),
                ),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: AppTypography.titleSmall.copyWith(color: AppColors.textPrimaryDark),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        displayEmail,
                        style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondaryDark),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.logout, color: AppColors.textSecondaryDark, size: AppSizes.iconSm),
                  tooltip: 'خروج',
                  onPressed: () {
                    context.read<AuthProvider>().logout();
                    context.go(AppRoutes.login);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}