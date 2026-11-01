import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_textfield.dart';
import '../../../core/widgets/custom_switch.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/theme_provider.dart';
import '../widgets/receipt_settings_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _companyNameController = TextEditingController();
  final _companyPhoneController = TextEditingController();
  final _companyAddressController = TextEditingController();
  final _minOrderController = TextEditingController();
  final _deliveryFeeController = TextEditingController();
  bool _syncedRemoteSettings = false;

  @override
  void dispose() {
    _companyNameController.dispose();
    _companyPhoneController.dispose();
    _companyAddressController.dispose();
    _minOrderController.dispose();
    _deliveryFeeController.dispose();
    super.dispose();
  }

  void _syncFromProvider(SettingsProvider provider) {
    if (!provider.hasLoaded || _syncedRemoteSettings) return;
    _syncedRemoteSettings = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _companyNameController.text = provider.companyName;
      _companyPhoneController.text = provider.companyPhone;
      _companyAddressController.text = provider.companyAddress;
      _minOrderController.text = provider.minDeliveryAmount?.toString() ?? '';
      _deliveryFeeController.text = provider.fixedDeliveryFee?.toString() ?? '';
      setState(() {});
    });
  }

  String _roleLabel(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
      case 'administrator':
        return 'مدیر';
      case 'manager':
        return 'مدیر فروشگاه';
      case 'staff':
        return 'کارمند';
      default:
        return 'کاربر';
    }
  }

  String _accountStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return 'فعال';
      case 'inactive':
        return 'غیرفعال';
      case 'blocked':
        return 'مسدود';
      case 'pending':
        return 'در انتظار تأیید';
      default:
        return 'نامشخص';
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
      ),
    );
  }

  Future<void> _saveSettings() async {
    final provider = context.read<SettingsProvider>();
    final success = await provider.saveSettings({
      'company_name': _companyNameController.text,
      'company_phone': _companyPhoneController.text,
      'company_address': _companyAddressController.text,
      'min_delivery_amount': _minOrderController.text.trim(),
      'fixed_delivery_fee': _deliveryFeeController.text.trim(),
    });
    if (!mounted) return;
    _showMessage(
      success ? 'تنظیمات ذخیره شد.' : (provider.error ?? 'ذخیره تنظیمات انجام نشد.'),
      isError: !success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final settings = context.watch<SettingsProvider>();
    final auth = context.watch<AuthProvider>();
    _syncFromProvider(settings);
    final currentUser = auth.currentUser;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSizes.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('تنظیمات پنل', style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: AppColors.getPrimaryText(context), fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSizes.lg),
          if (settings.isLoading && !settings.hasLoaded)
            const LinearProgressIndicator(),
          if (settings.error != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSizes.md),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(AppRadius.medium),
              ),
              child: Row(children: [
                const HugeIcon(icon: HugeIcons.strokeRoundedAlertCircle, color: AppColors.error),
                const SizedBox(width: AppSizes.sm),
                Expanded(child: Text(settings.error!, style: const TextStyle(color: AppColors.error))),
                IconButton(
                  tooltip: 'تلاش مجدد',
                  onPressed: settings.isLoading ? null : settings.reload,
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh, color: AppColors.info),
                ),
              ]),
            ),
            const SizedBox(height: AppSizes.lg),
          ],

          AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('اطلاعات کاربری', style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.getPrimaryText(context), fontWeight: FontWeight.bold)),
            const SizedBox(height: AppSizes.lg),
            Row(children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primary,
                backgroundImage: currentUser?.avatarUrl == null ? null : NetworkImage(currentUser!.avatarUrl!),
                child: currentUser?.avatarUrl == null ? const HugeIcon(icon: HugeIcons.strokeRoundedUser, color: Colors.white, size: 28) : null,
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(currentUser?.fullName ?? 'کاربر احراز هویت نشده', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(currentUser?.email ?? '', style: Theme.of(context).textTheme.bodyMedium),
                if (currentUser != null) Text('نقش: ${_roleLabel(currentUser.role)} · وضعیت: ${_accountStatusLabel(currentUser.status)}', style: Theme.of(context).textTheme.bodySmall),
              ])),
            ]),
            const SizedBox(height: AppSizes.md),
            const Text('اطلاعات حساب از پایگاه داده خوانده می‌شود. ویرایش نام و ایمیل حساب از این صفحه انجام نمی‌شود.'),
          ])),
          const SizedBox(height: AppSizes.lg),

          AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ظاهر برنامه', style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.getPrimaryText(context), fontWeight: FontWeight.bold)),
            const Divider(height: AppSizes.lg),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Row(children: [HugeIcon(icon: HugeIcons.strokeRoundedMoon02), SizedBox(width: AppSizes.sm), Text('حالت تیره')]),
              CustomSwitch(value: themeProvider.isDarkMode, onChanged: (_) => context.read<ThemeProvider>().toggleTheme()),
            ]),
          ])),
          const SizedBox(height: AppSizes.lg),

          AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('اطلاعات فروشگاه', style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.getPrimaryText(context), fontWeight: FontWeight.bold)),
            const SizedBox(height: AppSizes.lg),
            AppTextField(controller: _companyNameController, labelText: 'نام فروشگاه'),
            const SizedBox(height: AppSizes.md),
            AppTextField(controller: _companyPhoneController, labelText: 'شماره تماس', keyboardType: TextInputType.phone),
            const SizedBox(height: AppSizes.md),
            AppTextField(controller: _companyAddressController, labelText: 'آدرس', maxLines: 3),
          ])),
          const SizedBox(height: AppSizes.lg),

          AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('تنظیمات ارسال', style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.getPrimaryText(context), fontWeight: FontWeight.bold)),
            const Divider(height: AppSizes.lg),
            Wrap(spacing: AppSizes.md, runSpacing: AppSizes.md, children: [
              SizedBox(width: 260, child: AppTextField(controller: _minOrderController,
                labelText: 'حداقل مبلغ سفارش (تومان)', keyboardType: const TextInputType.numberWithOptions(decimal: true))),
              SizedBox(width: 260, child: AppTextField(controller: _deliveryFeeController,
                labelText: 'هزینه ثابت ارسال (تومان)', keyboardType: const TextInputType.numberWithOptions(decimal: true))),
            ]),
          ])),
          const SizedBox(height: AppSizes.lg),

          const ReceiptSettingsCard(),
          const SizedBox(height: AppSizes.lg),
          Align(alignment: Alignment.centerRight, child: AppButton(
            label: AppStrings.save,
            icon: Icons.save_outlined,
            isLoading: settings.isLoading,
            width: 180,
            onPressed: settings.isLoading ? null : _saveSettings,
          )),
        ],
      ),
    );
  }

  Widget _colorPickerItem(BuildContext context, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: Container(
        padding: const EdgeInsets.all(AppSizes.sm),
        decoration: BoxDecoration(border: Border.all(color: AppColors.getBorder(context)), borderRadius: BorderRadius.circular(AppRadius.medium)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 30, height: 30, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))),
          const SizedBox(width: AppSizes.sm),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(width: AppSizes.sm),
          const Icon(Icons.edit, size: 16, color: Colors.grey),
        ]),
      ),
    );
  }
}
