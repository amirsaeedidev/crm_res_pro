import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/logger_service.dart';
import '../core/services/supabase_service.dart';
import '../models/user_model.dart';

enum AuthLoginStepType {
  authenticated,
  verifyTotp,
  setupTotp,
}

/// A step in the CRM sign-in flow. A UserModel is returned only after the
/// current session has reached AAL2.
class AuthLoginStep {
  final AuthLoginStepType type;
  final UserModel? user;
  final String? factorId;
  final String? setupSecret;
  final String? setupQrCode;

  const AuthLoginStep({
    required this.type,
    this.user,
    this.factorId,
    this.setupSecret,
    this.setupQrCode,
  });
}

class AuthRepository {
  final SupabaseClient _client = Supabase.instance.client;
  final _auth = SupabaseService.auth;

  bool get hasActiveSession => _auth.currentSession != null;

  String? get currentUserId => _auth.currentUser?.id;

  Stream<AuthState> get authStateChanges => _auth.onAuthStateChange;

  String? get currentAssuranceLevel =>
      _auth.mfa.getAuthenticatorAssuranceLevel().currentLevel?.name;

  /// Signs in with the primary factor, then starts the TOTP step. For a CRM
  /// session without a verified authenticator, a new TOTP factor is enrolled
  /// and its secret/QR payload is returned for one-time setup.
  Future<AuthLoginStep> login(String email, String password) async {
    try {
      final response = await _auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      final user = response.user;
      if (user == null || response.session == null) {
        throw Exception('ورود انجام نشد. لطفاً دوباره تلاش کنید.');
      }

      return await _prepareMfaStep(user);
    } on AuthException catch (e, st) {
      LoggerService.error(
        'Authentication failed during login',
        error: e,
        stackTrace: st,
      );
      throw Exception(e.message);
    } on PostgrestException catch (e, st) {
      LoggerService.error(
        'Profile lookup failed during login',
        error: e,
        stackTrace: st,
      );
      throw Exception(
        'ورود اولیه انجام شد، اما خواندن پروفایل از دیتابیس ناموفق بود. '
        'دسترسی جدول profiles و سیاست‌های RLS را بررسی کنید.',
      );
    } catch (e, st) {
      LoggerService.error(
        'Unexpected login preparation error',
        error: e,
        stackTrace: st,
      );
      if (e is Exception && e.toString().startsWith('Exception: ')) {
        rethrow;
      }
      throw Exception(
        'آماده‌سازی ورود امن ناموفق بود. تنظیمات MFA را بررسی کنید.',
      );
    }
  }

  /// Prepares the MFA screen for a restored AAL1 session after an app restart.
  Future<AuthLoginStep> prepareCurrentSessionForLogin() async {
    final user = _auth.currentUser;
    if (user == null || _auth.currentSession == null) {
      throw Exception('نشست فعالی برای ادامه ورود وجود ندارد. دوباره وارد شوید.');
    }

    return _prepareMfaStep(user);
  }

  Future<AuthLoginStep> _prepareMfaStep(User user) async {
    final assurance = _auth.mfa.getAuthenticatorAssuranceLevel();
    if (assurance.currentLevel?.name == 'aal2') {
      final admin = await _loadAdminUser(user);
      return AuthLoginStep(
        type: AuthLoginStepType.authenticated,
        user: admin,
      );
    }

    final factors = await _auth.mfa.listFactors();
    Factor? verifiedTotp;
    for (final factor in factors.totp) {
      if (factor.status.name == 'verified') {
        verifiedTotp = factor;
        break;
      }
    }

    if (verifiedTotp != null) {
      return AuthLoginStep(
        type: AuthLoginStepType.verifyTotp,
        factorId: verifiedTotp.id,
      );
    }

    // Remove only incomplete TOTP enrollments left behind by an interrupted
    // setup. Verified factors are never removed here.
    for (final factor in factors.all) {
      if (factor.factorType.name == 'totp' &&
          factor.status.name == 'unverified') {
        await _auth.mfa.unenroll(factor.id);
      }
    }

    final enrollment = await _auth.mfa.enroll(
      factorType: FactorType.totp,
      issuer: 'Restaurant CRM',
      friendlyName: user.email ?? 'CRM administrator',
    );
    final totp = enrollment.totp;

    if (totp == null || totp.secret.trim().isEmpty) {
      throw Exception(
        'Supabase اطلاعات راه‌اندازی Authenticator را برنگرداند. دوباره تلاش کنید.',
      );
    }

    return AuthLoginStep(
      type: AuthLoginStepType.setupTotp,
      factorId: enrollment.id,
      setupSecret: totp.secret,
      setupQrCode: _decodeQrSvg(totp.qrCode),
    );
  }

  /// UUID format expected by Supabase Auth for a factor identifier.
  static final RegExp _factorIdPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// Resolves the factor ID again from Supabase instead of trusting a value
  /// passed through a screen/router. This avoids malformed or stale factor IDs
  /// accidentally producing a request such as `/factors/<partial-id>?...`.
  Future<String> _resolveVerifiedTotpFactorId(String requestedFactorId) async {
    final requested = requestedFactorId.trim();
    final factors = await _auth.mfa.listFactors();
    final verified = factors.totp
        .where((factor) => factor.status.name.toLowerCase() == 'verified')
        .toList(growable: false);

    if (verified.isEmpty) {
      throw Exception(
        'برای این حساب عامل Google Authenticator تأییدشده پیدا نشد. '
        'دوباره وارد شوید و وضعیت MFA را بررسی کنید.',
      );
    }

    // Prefer an exact match, but always return the canonical ID received from
    // Supabase rather than forwarding the UI's string to the REST client.
    for (final factor in verified) {
      final canonicalId = factor.id.trim();
      if (_factorIdPattern.hasMatch(canonicalId) && canonicalId == requested) {
        return canonicalId;
      }
    }

    // If the UI/router corrupted the ID and there is exactly one verified TOTP,
    // the server's factor listing is unambiguous and safe to use.
    if (verified.length == 1) {
      final canonicalId = verified.single.id.trim();
      if (_factorIdPattern.hasMatch(canonicalId)) return canonicalId;
    }

    if (!_factorIdPattern.hasMatch(requested)) {
      throw Exception(
        'شناسه عامل MFA از صفحه ورود معتبر نیست. صفحه را تازه‌سازی کنید '
        'و دوباره کد Authenticator را وارد کنید.',
      );
    }

    throw Exception(
      'عامل MFA انتخاب‌شده دیگر معتبر نیست یا به این نشست تعلق ندارد. '
      'صفحه را تازه‌سازی کنید و دوباره وارد شوید.',
    );
  }

  /// Verifies the six-digit authenticator code, confirms AAL2, and only then
  /// reads the admin profile. The role is never inferred from user metadata.
  Future<UserModel> verifyAuthenticatorCode({
    required String factorId,
    required String code,
  }) async {
    try {
      final normalizedCode = code.trim();
      if (!RegExp(r'^\d{6}$').hasMatch(normalizedCode)) {
        throw Exception('کد Google Authenticator باید دقیقاً ۶ رقم باشد.');
      }

      // Resolve a canonical factor ID from the current authenticated session.
      final canonicalFactorId =
          await _resolveVerifiedTotpFactorId(factorId);

      // Keep challenge and verify separate so any server-side AuthException is
      // attributable to the exact phase. Both endpoints use the SDK's normal
      // session/apikey headers; no custom URL construction is involved.
      final challenge = await _auth.mfa.challenge(
        factorId: canonicalFactorId,
      );
      await _auth.mfa.verify(
        factorId: canonicalFactorId,
        challengeId: challenge.id,
        code: normalizedCode,
      );

      final assurance = _auth.mfa.getAuthenticatorAssuranceLevel();
      if (assurance.currentLevel?.name != 'aal2') {
        throw Exception(
          'کد تأیید شد، اما سطح امن نشست به AAL2 نرسید. دوباره تلاش کنید.',
        );
      }

      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('نشست ورود منقضی شده است. دوباره وارد شوید.');
      }

      return await _loadAdminUser(user);
    } on AuthException catch (e, st) {
      LoggerService.error(
        'Authenticator verification failed',
        error: e,
        stackTrace: st,
      );
      throw Exception(e.message);
    } on PostgrestException catch (e, st) {
      LoggerService.error(
        'Profile lookup failed after MFA verification',
        error: e,
        stackTrace: st,
      );
      throw Exception(
        'کد Authenticator تأیید شد، اما خواندن پروفایل ناموفق بود. '
        'سیاست SELECT جدول profiles و RLS را بررسی کنید.',
      );
    } catch (e, st) {
      LoggerService.error(
        'Unexpected MFA verification error',
        error: e,
        stackTrace: st,
      );
      if (e is Exception && e.toString().startsWith('Exception: ')) {
        rethrow;
      }

      final errorText = e.toString().toLowerCase();
      if (errorText.contains('failed to fetch') ||
          errorText.contains('clientexception')) {
        throw Exception(
          'مرورگر نتوانست به سرویس MFA در Supabase وصل شود. '
          'شناسه عامل در کد دوباره از سرور خوانده می‌شود؛ اگر این خطا باقی '
          'ماند، تب Network/Console مرورگر را از نظر CORS یا خطای شبکه بررسی کنید.',
        );
      }
      throw Exception('تأیید کد Authenticator ناموفق بود.');
    }
  }

  /// Restore the current authenticated user only after the assurance level has
  /// already been checked by the caller.
  Future<UserModel?> getCurrentUser() async {
    final session = _auth.currentSession;
    if (session == null) return null;
    return _mapToUserModel(session.user);
  }

  /// Register a user. Registration never grants the admin role.
  Future<UserModel> signUp(String email, String password) async {
    try {
      final response = await _auth.signUp(
        email: email.trim(),
        password: password,
      );

      final user = response.user;
      if (user == null) {
        throw Exception('ثبت‌نام ناموفق بود. لطفاً دوباره تلاش کنید.');
      }

      LoggerService.info('User registered: ${user.id}');
      if (response.session == null) {
        return _buildUserModel(user, null);
      }

      return await _mapToUserModel(user);
    } on AuthException catch (e, st) {
      LoggerService.error(
        'Authentication failed during registration',
        error: e,
        stackTrace: st,
      );
      throw Exception(e.message);
    } on PostgrestException catch (e, st) {
      LoggerService.error(
        'Failed to load profile after registration',
        error: e,
        stackTrace: st,
      );
      throw Exception(
        'حساب ساخته شد، اما خواندن پروفایل ناموفق بود. '
        'جدول profiles و سیاست‌های RLS را بررسی کنید.',
      );
    } catch (e, st) {
      LoggerService.error(
        'Unexpected registration error',
        error: e,
        stackTrace: st,
      );
      if (e is Exception && e.toString().startsWith('Exception: ')) {
        rethrow;
      }
      throw Exception('خطای ناشناخته در زمان ثبت‌نام');
    }
  }

  Future<void> logout() async {
    try {
      await _auth.signOut();
      LoggerService.info('User logged out successfully');
    } on AuthException catch (e, st) {
      LoggerService.error(
        'Authentication error during logout',
        error: e,
        stackTrace: st,
      );
      throw Exception(e.message);
    } catch (e, st) {
      LoggerService.error(
        'Logout failed',
        error: e,
        stackTrace: st,
      );
      throw Exception('خطا در خروج از حساب کاربری');
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      await _auth.resetPasswordForEmail(email.trim());
      LoggerService.info('Password reset email requested');
    } on AuthException catch (e, st) {
      LoggerService.error(
        'Password reset authentication error',
        error: e,
        stackTrace: st,
      );
      throw Exception(e.message);
    } catch (e, st) {
      LoggerService.error(
        'Password reset failed',
        error: e,
        stackTrace: st,
      );
      throw Exception('خطا در ارسال ایمیل بازنشانی رمز عبور');
    }
  }

  Future<UserModel> _loadAdminUser(User user) async {
    final profile = await _client
        .from('profiles')
        .select('first_name, last_name, phone, avatar_url, role, status')
        .eq('id', user.id)
        .maybeSingle();

    // Do not collapse a missing/invisible profile, a wrong role, and a
    // disabled account into one misleading "inactive admin" message.
    if (profile == null) {
      throw Exception(
        'ورود و کد Authenticator تأیید شد، اما برای این حساب در جدول '
        'profiles پروفایلی پیدا نشد یا RLS آن را پنهان کرده است. '
        'ایمیل ورود: ${user.email ?? 'نامشخص'}؛ شناسه Auth: ${user.id}. '
        'بررسی کنید برنامه به همان پروژه Supabase متصل باشد و profiles.id '
        'با auth.users.id این حساب برابر باشد.',
      );
    }

    final role = profile['role']?.toString().trim().toLowerCase();
    final status = profile['status']?.toString().trim().toLowerCase();

    if (role != 'admin') {
      throw Exception(
        'کد Authenticator درست است، اما نقش این حساب در profiles برابر '
        '"${role ?? 'خالی'}" است، نه "admin". برای امنیت، ورود به پنل رد شد. '
        'ایمیل ورود: ${user.email ?? 'نامشخص'}.',
      );
    }

    if (status != 'active') {
      throw Exception(
        'کد Authenticator تأیید شد، اما وضعیت حساب در profiles برابر '
        '"${status ?? 'خالی'}" است، نه "active". '
        'ایمیل ورود: ${user.email ?? 'نامشخص'}.',
      );
    }

    return _buildUserModel(user, profile);
  }

  Future<UserModel> _mapToUserModel(User user) async {
    final profile = await _client
        .from('profiles')
        .select('first_name, last_name, phone, avatar_url, role, status')
        .eq('id', user.id)
        .maybeSingle();
    return _buildUserModel(user, profile);
  }

  UserModel _buildUserModel(
    User user,
    Map<String, dynamic>? profile,
  ) {
    final metadata = user.userMetadata ?? <String, dynamic>{};

    return UserModel(
      id: user.id,
      email: user.email ?? '',
      firstName: _asString(profile?['first_name']) ??
          _asString(metadata['first_name']),
      lastName: _asString(profile?['last_name']) ??
          _asString(metadata['last_name']),
      phone: _asString(profile?['phone']) ??
          _asString(user.phone) ??
          _asString(metadata['phone']),
      avatarUrl: _asString(profile?['avatar_url']) ??
          _asString(metadata['avatar_url']),
      // Authorization-sensitive fields are read from the database only.
      role: _asString(profile?['role']) ?? 'customer',
      status: _asString(profile?['status']) ?? 'active',
      createdAt: DateTime.tryParse(user.createdAt) ?? DateTime.now(),
    );
  }

  String? _asString(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  /// Supabase returns its QR as an SVG data URI. Normalize that value for the
  /// existing flutter_svg dependency. The secret remains available as a
  /// manual-entry fallback if the QR format changes.
  String? _decodeQrSvg(String qrCode) {
    try {
      if (qrCode.startsWith('data:image/svg+xml;base64,')) {
        final payload = qrCode.substring('data:image/svg+xml;base64,'.length);
        return utf8.decode(base64.decode(payload));
      }
      if (qrCode.startsWith('data:image/svg+xml;utf8,')) {
        return Uri.decodeComponent(
          qrCode.substring('data:image/svg+xml;utf8,'.length),
        );
      }
      if (qrCode.startsWith('data:image/svg+xml,')) {
        return Uri.decodeComponent(
          qrCode.substring('data:image/svg+xml,'.length),
        );
      }
      if (qrCode.trimLeft().startsWith('<svg')) return qrCode;
    } catch (e, st) {
      LoggerService.warning(
        'Could not parse authenticator QR payload',
      );
      LoggerService.debug('QR parsing exception: $e\n$st');
    }
    return null;
  }
}
