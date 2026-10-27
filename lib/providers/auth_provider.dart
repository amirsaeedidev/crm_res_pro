import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/logger_service.dart';
import '../core/utils/app_error_message.dart';
import '../core/services/storage_service.dart';
import '../models/user_model.dart';
import '../repositories/auth_repository.dart';

class AuthProvider extends ChangeNotifier {
  final AuthRepository _authRepository;

  StreamSubscription<AuthState>? _authSubscription;

  UserModel? _currentUser;
  bool _isLoading = true;
  bool _disposed = false;
  bool _loginFlowActive = false;
  bool _authRestoreInProgress = false;
  int _authStateVersion = 0;
  bool _mfaVerified = false;
  bool _requiresMfa = false;
  bool _mfaSetupRequired = false;

  String? _mfaFactorId;
  String? _mfaSetupSecret;
  String? _mfaSetupQrSvg;
  String? _errorMessage;
  String? _infoMessage;

  AuthProvider(this._authRepository) {
    _listenToAuthChanges();
  }

  UserModel? get currentUser => _currentUser;

  bool get isLoading => _isLoading;

  /// An authenticated CRM session must have reached AAL2, not just AAL1.
  bool get isAuthenticated =>
      _mfaVerified &&
      _currentUser != null &&
      _currentUser!.isAdmin &&
      _authRepository.hasActiveSession;

  bool get isAdmin => _currentUser?.isAdmin ?? false;

  bool get requiresMfa => _requiresMfa;

  bool get isMfaSetupRequired => _mfaSetupRequired;

  String? get mfaSetupSecret => _mfaSetupSecret;

  String? get mfaSetupQrSvg => _mfaSetupQrSvg;

  String? get errorMessage => _errorMessage;

  String? get infoMessage => _infoMessage;

  void _listenToAuthChanges() {
    _authSubscription = _authRepository.authStateChanges.listen(
      (state) {
        unawaited(_handleAuthStateChange(state));
      },
      onError: (Object error, StackTrace stackTrace) {
        LoggerService.error(
          'Auth state stream error',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
  }

  Future<void> _handleAuthStateChange(AuthState state) async {
    if (_disposed) return;

    // Supabase refreshes access tokens in the background. Re-reading the
    // profile and toggling `isLoading` for every refresh caused route flicker
    // and, when refresh events arrived close together, concurrent restoration
    // attempts. The current user's authorization is enforced by RLS on every
    // database request, so background token refresh must not restart login.
    if (state.event == AuthChangeEvent.tokenRefreshed ||
        state.event == AuthChangeEvent.userUpdated) {
      return;
    }

    final session = state.session;
    if (session == null) {
      // During sign-in Supabase may emit a SignedOut event for the previous
      // session before it emits SignedIn for the new one. Do not tear down the
      // in-flight password/MFA interaction in that interval.
      if (_loginFlowActive) return;

      _authStateVersion++;
      _currentUser = null;
      _mfaVerified = false;
      _clearMfaState();
      await _removeStoredUserId();
      if (!_disposed) {
        _isLoading = false;
        _notifyIfAlive();
      }
      return;
    }

    // Explicit login and MFA methods own the current flow. Also ignore a
    // duplicate event for a session that has already been fully authenticated.
    if (_loginFlowActive) return;
    if (_mfaVerified && _currentUser?.id == session.user.id) return;

    // More than one auth event can be emitted during a session transition.
    // Only one restoration/profile lookup may be active at a time.
    if (_authRestoreInProgress) return;
    _authRestoreInProgress = true;
    final restoreVersion = _authStateVersion;
    _isLoading = true;
    _notifyIfAlive();

    try {
      final step = await _authRepository.prepareCurrentSessionForLogin();
      if (_disposed ||
          restoreVersion != _authStateVersion ||
          !_authRepository.hasActiveSession ||
          _authRepository.currentUserId != session.user.id) {
        return;
      }
      await _applyLoginStep(step);
      LoggerService.info('Restored authentication state and MFA assurance');
    } catch (e, st) {
      // An auth transition may have superseded this async lookup. Never let a
      // stale result sign out or overwrite a newer session.
      if (restoreVersion != _authStateVersion) return;
      LoggerService.error(
        'Failed to restore or synchronize user profile',
        error: e,
        stackTrace: st,
      );
      _currentUser = null;
      _mfaVerified = false;
      _errorMessage = _readableError(e);
      _clearMfaState();
      await _removeStoredUserId();
      // A stale or unusable session must not remain in the CRM.
      try {
        await _authRepository.logout();
      } catch (_) {
        // Keep the original restoration error visible.
      }
    } finally {
      _authRestoreInProgress = false;
      if (!_disposed) {
        // Restoring an AAL1 session may intentionally leave the login flow
        // active while the MFA form is shown. Loading must still end here;
        // otherwise LoginRouteGuard keeps displaying its spinner forever.
        _isLoading = false;
        _notifyIfAlive();
      }
    }
  }

  /// Primary sign-in. If MFA is enabled, the UI remains on the login route
  /// until [verifyAuthenticatorCode] completes successfully.
  Future<void> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    _infoMessage = null;
    _authStateVersion++;
    _loginFlowActive = true;
    _currentUser = null;
    _mfaVerified = false;
    _clearMfaState();
    _notifyIfAlive();

    try {
      final step = await _authRepository.login(email, password);
      if (_disposed) return;
      await _applyLoginStep(step);

      if (step.type == AuthLoginStepType.authenticated) {
        _loginFlowActive = false;
        LoggerService.info('Administrator completed sign-in');
      } else {
        // Keep the guard active while the user enters the authenticator code.
        _loginFlowActive = true;
      }
    } catch (e, st) {
      _loginFlowActive = false;
      _currentUser = null;
      _mfaVerified = false;
      _clearMfaState();
      _errorMessage = _readableError(e);
      LoggerService.error('Login failed', error: e, stackTrace: st);
      try {
        await _authRepository.logout();
      } catch (_) {
        // Preserve the login error; no elevated access is granted.
      }
    } finally {
      if (!_disposed) {
        _isLoading = false;
        _notifyIfAlive();
      }
    }
  }

  /// Verifies an authenticator code. This is also the activation step for a
  /// new TOTP factor if [isMfaSetupRequired] is true.
  Future<void> verifyAuthenticatorCode(String code) async {
    if (_mfaFactorId == null) {
      _errorMessage = 'اطلاعات برنامه رمزساز در دسترس نیست. دوباره وارد شوید.';
      _notifyIfAlive();
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code.trim())) {
      _errorMessage = 'کد برنامه رمزساز باید دقیقاً ۶ رقم باشد.';
      _notifyIfAlive();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    _notifyIfAlive();

    try {
      final user = await _authRepository.verifyAuthenticatorCode(
        factorId: _mfaFactorId!,
        code: code.trim(),
      );
      if (_disposed) return;

      _currentUser = user;
      _mfaVerified = true;
      _loginFlowActive = false;
      _clearMfaState();
      await _storeUserId(user.id);
      LoggerService.info('Administrator passed authenticator MFA');
    } catch (e, st) {
      _errorMessage = _readableError(e);
      LoggerService.error(
        'Authenticator code verification failed',
        error: e,
        stackTrace: st,
      );

      // If Supabase ended the session (for example, because the authenticated
      // account is not an active CRM admin), return to the primary login form.
      // Also leave the MFA form if AAL2 succeeded but profile RLS blocked the
      // final admin lookup; keeping an already-verified challenge on screen
      // would be misleading.
      final sessionEnded = !_authRepository.hasActiveSession;
      final assuranceWasRaised =
          _authRepository.currentAssuranceLevel == 'aal2';
      if (sessionEnded || assuranceWasRaised) {
        _loginFlowActive = false;
        _currentUser = null;
        _mfaVerified = false;
        _clearMfaState();
        await _removeStoredUserId();
        if (assuranceWasRaised && !sessionEnded) {
          try {
            await _authRepository.logout();
          } catch (_) {
            // Preserve the profile/RLS error.
          }
        }
      }
    } finally {
      if (!_disposed) {
        _isLoading = false;
        _notifyIfAlive();
      }
    }
  }

  /// Cancels an incomplete MFA flow and clears the primary Supabase session.
  Future<void> cancelMfaLogin() async {
    _isLoading = true;
    _errorMessage = null;
    _infoMessage = null;
    _notifyIfAlive();

    _loginFlowActive = false;
    try {
      await _authRepository.logout();
    } catch (e, st) {
      LoggerService.error(
        'Failed to cancel pending MFA login',
        error: e,
        stackTrace: st,
      );
    } finally {
      _currentUser = null;
      _mfaVerified = false;
      _clearMfaState();
      await _removeStoredUserId();
      if (!_disposed) {
        _isLoading = false;
        _notifyIfAlive();
      }
    }
  }

  Future<void> _applyLoginStep(AuthLoginStep step) async {
    switch (step.type) {
      case AuthLoginStepType.authenticated:
        _loginFlowActive = false;
        final user = step.user;
        if (user == null) {
          throw Exception('اطلاعات حساب مدیر دریافت نشد.');
        }
        _currentUser = user;
        _mfaVerified = true;
        _clearMfaState();
        await _storeUserId(user.id);
        break;
      case AuthLoginStepType.verifyTotp:
        _loginFlowActive = true;
        _currentUser = null;
        _mfaVerified = false;
        _requiresMfa = true;
        _mfaSetupRequired = false;
        _mfaFactorId = step.factorId;
        _mfaSetupSecret = null;
        _mfaSetupQrSvg = null;
        await _removeStoredUserId();
        break;
      case AuthLoginStepType.setupTotp:
        _loginFlowActive = true;
        _currentUser = null;
        _mfaVerified = false;
        _requiresMfa = true;
        _mfaSetupRequired = true;
        _mfaFactorId = step.factorId;
        _mfaSetupSecret = step.setupSecret;
        _mfaSetupQrSvg = step.setupQrCode;
        _infoMessage =
            'برنامه رمزساز هنوز به این حساب متصل نیست. ابتدا آن را راه‌اندازی کنید و سپس کد ۶ رقمی را وارد کنید.';
        await _removeStoredUserId();
        break;
    }
  }

  void _clearMfaState() {
    _requiresMfa = false;
    _mfaSetupRequired = false;
    _mfaFactorId = null;
    _mfaSetupSecret = null;
    _mfaSetupQrSvg = null;
  }

  String _readableError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    return AppErrorMessage.forDisplay(
      message,
      fallback: 'ورود یا بررسی هویت ناموفق بود. اطلاعات واردشده را بررسی کنید و دوباره تلاش کنید.',
    );
  }

  Future<void> register(String email, String password) async {
    _isLoading = true;
    _loginFlowActive = true;
    _errorMessage = null;
    _infoMessage = null;
    _notifyIfAlive();

    try {
      await _authRepository.signUp(email, password);
      if (_disposed) return;

      // Sign-up never grants CRM admin access. A new account must sign in and
      // pass the same admin + MFA checks as every other account.
      _currentUser = null;
      _mfaVerified = false;
      await _removeStoredUserId();
      _infoMessage = 'ثبت‌نام انجام شد. برای ورود، ایمیل خود را تأیید کنید.';
      await _authRepository.logout();
    } catch (e, st) {
      _errorMessage = _readableError(e);
      LoggerService.error('Registration failed', error: e, stackTrace: st);
    } finally {
      _loginFlowActive = false;
      if (!_disposed) {
        _isLoading = false;
        _notifyIfAlive();
      }
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    _errorMessage = null;
    _infoMessage = null;
    _loginFlowActive = false;
    _authStateVersion++;
    _notifyIfAlive();

    try {
      await _authRepository.logout();
      if (_disposed) return;
      _currentUser = null;
      _mfaVerified = false;
      _clearMfaState();
      await _removeStoredUserId();
      LoggerService.info('User logged out successfully');
    } catch (e, st) {
      _errorMessage = _readableError(e);
      LoggerService.error('Logout failed', error: e, stackTrace: st);
    } finally {
      if (!_disposed) {
        _isLoading = false;
        _notifyIfAlive();
      }
    }
  }

  Future<void> _storeUserId(String userId) async {
    try {
      await StorageService.setString('user_id', userId);
    } catch (e, st) {
      LoggerService.error(
        'Failed to cache user ID',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _removeStoredUserId() async {
    try {
      await StorageService.remove('user_id');
    } catch (e, st) {
      LoggerService.error(
        'Failed to remove cached user ID',
        error: e,
        stackTrace: st,
      );
    }
  }

  void clearError() {
    _errorMessage = null;
    _notifyIfAlive();
  }

  void clearInfo() {
    _infoMessage = null;
    _notifyIfAlive();
  }

  void _notifyIfAlive() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _authSubscription?.cancel();
    super.dispose();
  }
}
