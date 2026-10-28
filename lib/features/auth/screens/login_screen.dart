import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_textfield.dart';
import '../../../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _loginFormKey = GlobalKey<FormState>();
  final _mfaFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submitLogin() async {
    final provider = context.read<AuthProvider>();
    if (provider.isLoading || !_loginFormKey.currentState!.validate()) return;

    await provider.login(
      _emailController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;
    if (provider.isAuthenticated) {
      context.go(AppRoutes.dashboard);
    }
  }

  Future<void> _submitAuthenticatorCode() async {
    final provider = context.read<AuthProvider>();
    if (provider.isLoading || !_mfaFormKey.currentState!.validate()) return;

    await provider.verifyAuthenticatorCode(_codeController.text.trim());

    if (!mounted) return;
    if (provider.isAuthenticated) {
      context.go(AppRoutes.dashboard);
    }
  }

  Future<void> _cancelMfa() async {
    await context.read<AuthProvider>().cancelMfaLogin();
    if (!mounted) return;
    _codeController.clear();
  }

  Future<void> _copySetupSecret(String secret) async {
    await Clipboard.setData(ClipboardData(text: secret));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('کلید راه‌اندازی کپی شد.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppColors.getBackground(context),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSizes.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context),
                const SizedBox(height: AppSizes.xl),
                Text(
                  provider.requiresMfa
                      ? (provider.isMfaSetupRequired
                          ? 'اتصال Google Authenticator'
                          : 'تأیید هویت مدیر')
                      : AppStrings.welcomeBack,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.getPrimaryText(context),
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSizes.sm),
                Text(
                  provider.requiresMfa
                      ? (provider.isMfaSetupRequired
                          ? 'برای محافظت از پنل، اپ Authenticator را یک‌بار به حساب متصل کنید.'
                          : 'کد فعلی اپ Google Authenticator را وارد کنید.')
                      : 'لطفاً برای ادامه با حساب مدیر وارد شوید.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.getSecondaryText(context),
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSizes.xl),
                if (provider.errorMessage != null) ...[
                  _buildMessage(
                    context,
                    provider.errorMessage!,
                    isError: true,
                  ),
                  const SizedBox(height: AppSizes.md),
                ],
                if (provider.infoMessage != null &&
                    provider.errorMessage == null) ...[
                  _buildMessage(context, provider.infoMessage!),
                  const SizedBox(height: AppSizes.md),
                ],
                if (provider.requiresMfa)
                  _buildMfaForm(context, provider)
                else
                  _buildLoginForm(context, provider),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.extraLarge),
      ),
      child: Column(
        children: [
          const Icon(Icons.restaurant_menu, size: 64, color: Colors.white),
          const SizedBox(height: AppSizes.md),
          Text(
            'پنل مدیریت رستوران',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLoginForm(BuildContext context, AuthProvider provider) {
    return Form(
      key: _loginFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _emailController,
            labelText: AppStrings.email,
            hintText: 'admin@example.com',
            keyboardType: TextInputType.emailAddress,
            prefixIcon: const Icon(Icons.email_outlined, size: 20),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'ایمیل الزامی است';
              }
              if (!RegExp(r'^[\w.\-+]+@([\w-]+\.)+[\w-]{2,}$')
                  .hasMatch(value.trim())) {
                return 'فرمت ایمیل نامعتبر است';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSizes.md),
          AppTextField(
            controller: _passwordController,
            labelText: AppStrings.password,
            hintText: '********',
            obscureText: _obscurePassword,
            prefixIcon: const Icon(Icons.lock_outline, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
                color: AppColors.getSecondaryText(context),
              ),
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'رمز عبور الزامی است';
              if (value.length < 6) return 'رمز عبور حداقل ۶ کاراکتر باشد';
              return null;
            },
            onFieldSubmitted: (_) => _submitLogin(),
          ),
          const SizedBox(height: AppSizes.lg),
          AppButton(
            label: AppStrings.login,
            icon: Icons.lock_open_rounded,
            isLoading: provider.isLoading,
            onPressed: provider.isLoading ? null : _submitLogin,
          ),
        ],
      ),
    );
  }

  Widget _buildMfaForm(BuildContext context, AuthProvider provider) {
    final secret = provider.mfaSetupSecret;
    final qrSvg = provider.mfaSetupQrSvg;

    return Form(
      key: _mfaFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (provider.isMfaSetupRequired && secret != null) ...[
            Container(
              padding: const EdgeInsets.all(AppSizes.md),
              decoration: BoxDecoration(
                color: AppColors.getSurface(context),
                borderRadius: BorderRadius.circular(AppRadius.large),
                border: Border.all(color: AppColors.getBorder(context)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.security_rounded, size: 34),
                  const SizedBox(height: AppSizes.sm),
                  Text(
                    '۱. در Google Authenticator گزینه افزودن حساب را بزنید.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSizes.sm),
                  if (qrSvg != null)
                    Container(
                      padding: const EdgeInsets.all(AppSizes.sm),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.medium),
                      ),
                      child: SvgPicture.string(
                        qrSvg,
                        width: 190,
                        height: 190,
                        fit: BoxFit.contain,
                      ),
                    ),
                  if (qrSvg != null) const SizedBox(height: AppSizes.sm),
                  Text(
                    qrSvg == null
                        ? 'اگر امکان اسکن QR ندارید، کلید زیر را به‌صورت دستی وارد کنید.'
                        : 'اگر QR اسکن نشد، کلید راه‌اندازی را به‌صورت دستی وارد کنید.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.getSecondaryText(context),
                        ),
                  ),
                  const SizedBox(height: AppSizes.sm),
                  SelectableText(
                    secret,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                  ),
                  TextButton.icon(
                    onPressed: () => _copySetupSecret(secret),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('کپی کلید راه‌اندازی'),
                  ),
                  const SizedBox(height: AppSizes.xs),
                  Text(
                    'نوع کد: مبتنی بر زمان (Time-based)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.getSecondaryText(context),
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSizes.lg),
            Text(
              '۲. کد ۶ رقمی نمایش‌داده‌شده در Authenticator را وارد کنید تا اتصال فعال شود.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSizes.md),
          ] else ...[
            const Icon(Icons.verified_user_outlined, size: 44),
            const SizedBox(height: AppSizes.sm),
            Text(
              'اپ Google Authenticator را باز کنید و کد ۶ رقمی حساب مدیر را وارد کنید. کد به‌صورت دوره‌ای تغییر می‌کند.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSizes.lg),
          ],
          AppTextField(
            controller: _codeController,
            labelText: 'کد ۶ رقمی Authenticator',
            hintText: '000000',
            keyboardType: TextInputType.number,
            prefixIcon: const Icon(Icons.password_rounded, size: 20),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'کد تأیید الزامی است';
              }
              if (!RegExp(r'^\d{6}$').hasMatch(value.trim())) {
                return 'کد باید دقیقاً ۶ رقم باشد';
              }
              return null;
            },
            onFieldSubmitted: (_) => _submitAuthenticatorCode(),
          ),
          const SizedBox(height: AppSizes.lg),
          AppButton(
            label: provider.isMfaSetupRequired
                ? 'فعال‌سازی و ورود'
                : 'تأیید کد و ورود',
            icon: Icons.verified_user_outlined,
            isLoading: provider.isLoading,
            onPressed: provider.isLoading ? null : _submitAuthenticatorCode,
          ),
          const SizedBox(height: AppSizes.sm),
          TextButton.icon(
            onPressed: provider.isLoading ? null : _cancelMfa,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('لغو و بازگشت به ورود'),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    final color = isError ? AppColors.error : AppColors.primary;
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isError ? AppColors.error : AppColors.getPrimaryText(context),
            ),
      ),
    );
  }
}
