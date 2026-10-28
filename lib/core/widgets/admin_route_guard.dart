import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../constants/app_routes.dart';

/// Prevents unauthenticated or non-admin users from opening CRM screens.
/// RLS remains the final authorization layer; this guard is only UI routing.
class AdminRouteGuard extends StatefulWidget {
  final Widget child;

  const AdminRouteGuard({super.key, required this.child});

  @override
  State<AdminRouteGuard> createState() => _AdminRouteGuardState();
}

class _AdminRouteGuardState extends State<AdminRouteGuard> {
  bool _redirectQueued = false;

  void _redirectToLogin() {
    if (_redirectQueued) return;
    _redirectQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(AppRoutes.login);
      _redirectQueued = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!auth.isAuthenticated || !auth.isAdmin) {
      _redirectToLogin();
      return const Scaffold(
        body: Center(child: Text('برای دسترسی به پنل، ورود مدیر لازم است.')),
      );
    }

    return widget.child;
  }
}

/// Restores an already-authenticated administrator to the dashboard instead
/// of showing the login form on every application restart.
class LoginRouteGuard extends StatefulWidget {
  final Widget child;

  const LoginRouteGuard({super.key, required this.child});

  @override
  State<LoginRouteGuard> createState() => _LoginRouteGuardState();
}

class _LoginRouteGuardState extends State<LoginRouteGuard> {
  bool _redirectQueued = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (auth.isAuthenticated && auth.isAdmin) {
      if (!_redirectQueued) {
        _redirectQueued = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.go(AppRoutes.dashboard);
        });
      }
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    _redirectQueued = false;
    return widget.child;
  }
}
