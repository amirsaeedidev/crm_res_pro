import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
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
  final bool drawerMode;

  const AppSidebar({super.key, this.drawerMode = false});

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

    return SafeArea(
      top: drawerMode,
      bottom: drawerMode,
      child: Container(
      width: AppSizes.sidebarWidth,
      color: drawerMode
          ? (Theme.of(context).brightness == Brightness.dark
              ? Colors.black
              : const Color(0xFF0077B6))
          : AppColors.surfaceDark,
      child: Column(
        children: [
          // Logo Header
          Container(
            height: AppSizes.topBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                HugeIcon(icon: HugeIcons.strokeRoundedDashboardSquare01, color: drawerMode ? Colors.white : AppColors.primary, size: AppSizes.iconLg),
                const SizedBox(width: AppSizes.sm),
                Text(
                  AppStrings.appName,
                  style: AppTypography.headlineMedium.copyWith(
                    color: drawerMode ? Colors.white : AppColors.textPrimaryDark,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Divider(color: drawerMode ? Colors.white.withValues(alpha: 0.35) : AppColors.borderDark, height: 1),
          
          // Menu Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                vertical: AppSizes.md,
                horizontal: AppSizes.sm,
              ),
              children: [
                NavigationItem(
                  forceWhite: drawerMode,
                  icon: HugeIcons.strokeRoundedHome01,
                  label: AppStrings.dashboard,
                  isActive: navProvider.selectedIndex == 0,
                  onTap: () {
                    navProvider.updateIndex(0);
                    if (drawerMode) Navigator.of(context).pop();
                    context.push(AppRoutes.dashboard);
                  },
                ),
                NavigationItem(
                  forceWhite: drawerMode,
                  icon: HugeIcons.strokeRoundedShoppingBag01,
                  label: AppStrings.orders,
                  isActive: navProvider.selectedIndex == 1,
                  onTap: () {
                    navProvider.updateIndex(1);
                    if (drawerMode) Navigator.of(context).pop();
                    context.push(AppRoutes.orders);
                  },
                ),
                NavigationItem(
                  forceWhite: drawerMode,
                  icon: HugeIcons.strokeRoundedServingFood,
                  label: AppStrings.products,
                  isActive: navProvider.selectedIndex == 2,
                  onTap: () {
                    navProvider.updateIndex(2);
                    if (drawerMode) Navigator.of(context).pop();
                    context.push(AppRoutes.products);
                  },
                ),
                NavigationItem(
                  forceWhite: drawerMode,
                  icon: HugeIcons.strokeRoundedUserGroup,
                  label: AppStrings.customers,
                  isActive: navProvider.selectedIndex == 3,
                  onTap: () {
                    navProvider.updateIndex(3);
                    if (drawerMode) Navigator.of(context).pop();
                    context.push(AppRoutes.customers);
                  },
                ),
                NavigationItem(
                  forceWhite: drawerMode,
                  icon: HugeIcons.strokeRoundedAiSwap,
                  label: AppStrings.categories,
                  isActive: navProvider.selectedIndex == 4,
                  onTap: () {
                    navProvider.updateIndex(4);
                    if (drawerMode) Navigator.of(context).pop();
                    context.push(AppRoutes.categories);
                  },
                ),
                NavigationItem(
                  forceWhite: drawerMode,
                  icon: HugeIcons.strokeRoundedChart01,
                  label: AppStrings.reports,
                  isActive: navProvider.selectedIndex == 5,
                  onTap: () {
                    navProvider.updateIndex(5);
                    if (drawerMode) Navigator.of(context).pop();
                    context.push(AppRoutes.reports);
                  },
                ),
                NavigationItem(
                  forceWhite: drawerMode,
                  icon: HugeIcons.strokeRoundedTableRound,
                  label: 'میزها',
                  isActive: navProvider.selectedIndex == 7,
                  onTap: () {
                    navProvider.updateIndex(7);
                    if (drawerMode) Navigator.of(context).pop();
                    context.push(AppRoutes.tables);
                  },
                ),
                NavigationItem(
                  forceWhite: drawerMode,
                  icon: HugeIcons.strokeRoundedCalendarCheckIn01,
                  label: 'رزروها',
                  isActive: navProvider.selectedIndex == 8,
                  onTap: () {
                    navProvider.updateIndex(8);
                    if (drawerMode) Navigator.of(context).pop();
                    context.push(AppRoutes.reservations);
                  },
                ),
                NavigationItem(
                  forceWhite: drawerMode,
                  icon: HugeIcons.strokeRoundedMegaphone01,
                  label: 'بنرها',
                  isActive: navProvider.selectedIndex == 9,
                  onTap: () { navProvider.updateIndex(9); if (drawerMode) Navigator.of(context).pop();
                    context.push('/banners'); },
                ),
                NavigationItem(
                  forceWhite: drawerMode,
                  icon: HugeIcons.strokeRoundedTag01,
                  label: 'تخفیف‌ها',
                  isActive: navProvider.selectedIndex == 10,
                  onTap: () { navProvider.updateIndex(10); if (drawerMode) Navigator.of(context).pop();
                    context.push('/discounts'); },
                ),
                NavigationItem(
                  forceWhite: drawerMode,
                  icon: HugeIcons.strokeRoundedHeadset,
                  label: 'تیکت‌ها',
                  isActive: navProvider.selectedIndex == 11,
                  onTap: () { navProvider.updateIndex(11); if (drawerMode) Navigator.of(context).pop();
                    context.push(AppRoutes.tickets); },
                ),
                NavigationItem(
                  forceWhite: drawerMode,
                  icon: HugeIcons.strokeRoundedFolderOpen,
                  label: 'مدیریت فایل‌ها',
                  isActive: navProvider.selectedIndex == 12,
                  onTap: () { navProvider.updateIndex(12); if (drawerMode) Navigator.of(context).pop();
                    context.push(AppRoutes.files); },
                ),
                NavigationItem(
                  forceWhite: drawerMode,
                  icon: HugeIcons.strokeRoundedGift,
                  label: 'باشگاه مشتریان',
                  isActive: navProvider.selectedIndex == 13,
                  onTap: () { navProvider.updateIndex(13); if (drawerMode) Navigator.of(context).pop();
                    context.push(AppRoutes.loyalty); },
                ),
                NavigationItem(
                  forceWhite: drawerMode,
                  icon: HugeIcons.strokeRoundedMessage02,
                  label: 'مرکز پیامک',
                  isActive: navProvider.selectedIndex == 14,
                  onTap: () { navProvider.updateIndex(14); if (drawerMode) Navigator.of(context).pop();
                    context.push(AppRoutes.sms); },
                ),
                NavigationItem(
                  forceWhite: drawerMode,
                  icon: HugeIcons.strokeRoundedWarehouse,
                  label: 'انبارداری و مواد اولیه',
                  isActive: navProvider.selectedIndex == 15,
                  onTap: () { navProvider.updateIndex(15); if (drawerMode) Navigator.of(context).pop();
                    context.push(AppRoutes.inventory); },
                ),
                NavigationItem(
                  forceWhite: drawerMode,
                  icon: HugeIcons.strokeRoundedWallet01,
                  label: 'کیف پول مالی مشتریان',
                  isActive: navProvider.selectedIndex == 16,
                  onTap: () { navProvider.updateIndex(16); if (drawerMode) Navigator.of(context).pop();
                    context.push(AppRoutes.wallets); },
                ),
                NavigationItem(
                  forceWhite: drawerMode,
                  icon: HugeIcons.strokeRoundedNotification01,
                  label: 'مدیریت اعلان‌ها',
                  isActive: navProvider.selectedIndex == 17,
                  onTap: () { navProvider.updateIndex(17); if (drawerMode) Navigator.of(context).pop();
                    context.push(AppRoutes.notifications); },
                ),
                NavigationItem(
                  forceWhite: drawerMode,
                  icon: HugeIcons.strokeRoundedSettings01,
                  label: AppStrings.settings,
                  isActive: navProvider.selectedIndex == 6,
                  onTap: () {
                    navProvider.updateIndex(6);
                    if (drawerMode) Navigator.of(context).pop();
                    context.push(AppRoutes.settings);
                  },
                ),
              ],
            ),
          ),
          
          // Footer User Info
          Container(
            padding: const EdgeInsets.all(AppSizes.md),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: drawerMode ? Colors.white.withValues(alpha: 0.35) : AppColors.borderDark, width: 1)),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: AppColors.primary,
                  child: HugeIcon(icon: HugeIcons.strokeRoundedUser, color: Colors.white),
                ),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: AppTypography.titleSmall.copyWith(color: drawerMode ? Colors.white : AppColors.textPrimaryDark),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        displayEmail,
                        style: AppTypography.bodySmall.copyWith(color: drawerMode ? Colors.white : AppColors.textSecondaryDark),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedLogout01, color: drawerMode ? Colors.white : AppColors.textSecondaryDark, size: AppSizes.iconSm),
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
      ),
    );
  }
}