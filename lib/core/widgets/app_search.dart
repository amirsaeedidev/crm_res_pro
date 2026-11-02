import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../constants/app_strings.dart';
import '../theme/app_radius.dart';
import '../theme/app_typography.dart';

class AppSearch extends StatefulWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final String hintText;
  final bool autoFocus;
  final bool useHugeIcons;

  const AppSearch({
    super.key,
    this.controller,
    this.onChanged,
    this.onClear,
    this.hintText = AppStrings.search,
    this.autoFocus = false,
    this.useHugeIcons = false,
  });

  @override
  State<AppSearch> createState() => _AppSearchState();
}

class _AppSearchState extends State<AppSearch> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant AppSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _controller.removeListener(_handleControllerChanged);
      if (oldWidget.controller == null) _controller.dispose();
      _controller = widget.controller ?? TextEditingController();
      _controller.addListener(_handleControllerChanged);
    }
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
    widget.onClear?.call();
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      autofocus: widget.autoFocus,
      textInputAction: TextInputAction.search,
      autocorrect: false,
      enableSuggestions: true,
      style: AppTypography.bodyMedium.copyWith(color: AppColors.getPrimaryText(context)),
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.getSecondaryText(context)),
        prefixIcon: widget.useHugeIcons
            ? HugeIcon(icon: HugeIcons.strokeRoundedSearch01, color: AppColors.getSecondaryText(context), size: AppSizes.iconSm)
            : Icon(Icons.search, color: AppColors.getSecondaryText(context), size: AppSizes.iconSm),
        suffixIcon: _controller.text.isNotEmpty
            ? IconButton(
                tooltip: 'پاک‌کردن جست‌وجو',
                icon: widget.useHugeIcons
                    ? HugeIcon(icon: HugeIcons.strokeRoundedCancel01, color: AppColors.getSecondaryText(context), size: AppSizes.iconSm)
                    : Icon(Icons.close, color: AppColors.getSecondaryText(context), size: AppSizes.iconSm),
                onPressed: _clear,
              )
            : null,
        filled: true,
        fillColor: AppColors.getSurface(context),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.sm),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.circular),
          borderSide: BorderSide(color: AppColors.getBorder(context), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.circular),
          borderSide: BorderSide(color: AppColors.getBorder(context), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.circular),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}
