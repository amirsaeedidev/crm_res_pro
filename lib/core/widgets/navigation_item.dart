import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../theme/app_typography.dart';
import '../theme/app_radius.dart';

class NavigationItem extends StatelessWidget {
  final IconData icon;
  final String? imageAssetPath;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const NavigationItem({
    super.key,
    required this.icon,
    this.imageAssetPath,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.md,
            vertical: AppSizes.sm,
          ),
          decoration: BoxDecoration(
            // Fixed: Replaced deprecated withOpacity with withValues
            color: isActive ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
          child: Row(
            children: [
              if (imageAssetPath != null)
                Image.asset(
                  imageAssetPath!,
                  width: AppSizes.iconMd + 4,
                  height: AppSizes.iconMd + 4,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    icon,
                    color: isActive ? AppColors.primary : AppColors.getSecondaryText(context),
                    size: AppSizes.iconMd + 4,
                  ),
                )
              else
                Icon(
                  icon,
                  color: isActive ? AppColors.primary : AppColors.getSecondaryText(context),
                  size: AppSizes.iconMd + 4,
                ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.titleMedium.copyWith(
                    color: isActive ? AppColors.primary : AppColors.getPrimaryText(context),
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              if (isActive)
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppRadius.circular),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}