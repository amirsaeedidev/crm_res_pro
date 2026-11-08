import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';
import 'package:provider/provider.dart';
import 'providers.dart';
import 'router.dart';
import 'theme.dart';
import '../providers/theme_provider.dart';
import '../providers/navigation_provider.dart';
import '../core/constants/app_strings.dart';

class CrmApp extends StatelessWidget {
  const CrmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: AppProviders.providers,
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp.router(
            title: AppStrings.appName,
            locale: const Locale('fa', 'IR'),
            supportedLocales: const [Locale('fa', 'IR')],
            localizationsDelegates: const [
              PersianMaterialLocalizations.delegate,
              PersianCupertinoLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            routerConfig: AppRouter.router,
            // Preserve the route stack on Android: pushed forms/details pop first.
            // At the shell root, restore the previous section instead of exiting.
            builder: (context, child) {
              final router = AppRouter.router;
              return PopScope<Object?>(
                canPop: router.canPop(),
                onPopInvokedWithResult: (didPop, result) {
                  if (didPop) return;
                  final previousRoute =
                      context.read<NavigationProvider>().goBack();
                  if (previousRoute != null) {
                    router.go(previousRoute);
                  }
                },
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: child ?? const SizedBox.shrink(),
                ),
              );
            },
          );
        },
      ),
    );
  }
}