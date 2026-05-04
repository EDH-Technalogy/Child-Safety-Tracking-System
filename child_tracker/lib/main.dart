import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/child_provider.dart';
import 'providers/location_provider.dart';
import 'providers/alert_provider.dart';
import 'providers/geofence_provider.dart';
import 'providers/activity_provider.dart';
import 'providers/device_live_tracking_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/notification_provider.dart';
import 'l10n/app_localizations.dart';
import 'l10n/cupertino_fallback_localizations.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/otp_verification_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/home_screen.dart';
import 'screens/child_detail_screen.dart';
import 'screens/location_history_screen.dart';
import 'screens/alerts_screen.dart';
import 'screens/safe_zones_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/about_screen.dart';
import 'screens/add_child_screen.dart';
import 'screens/add_safe_zone_screen.dart';
import 'screens/activity_screen.dart';
import 'screens/map_screen.dart';
import 'screens/admin/admin_login_screen.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'screens/edit_child_screen.dart';
import 'services/notification_service.dart';
import 'services/sos_alert_debug_logger.dart';
import 'utils/constants.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase initialization remains disabled until firebase_options.dart
  // is generated for this project environment.
  // await Firebase.initializeApp(
  //   options: DefaultFirebaseOptions.currentPlatform,
  // );
  // Firebase.init commented to avoid errors until configured
  // await Firebase.initializeApp();
  final localeProvider = await LocaleProvider.load();
  await NotificationService().init();
  unawaited(SOSAlertDebugLogger.start());
  runApp(MyApp(localeProvider: localeProvider));
}

class MyApp extends StatelessWidget {
  final LocaleProvider? localeProvider;

  const MyApp({super.key, this.localeProvider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ChildProvider()),
        ChangeNotifierProvider(create: (_) => LocationProvider()),
        ChangeNotifierProvider(create: (_) => AlertProvider()),
        ChangeNotifierProvider(create: (_) => GeofenceProvider()),
        ChangeNotifierProvider(create: (_) => ActivityProvider()),
        ChangeNotifierProvider(create: (_) => DeviceLiveTrackingProvider()),
        if (localeProvider != null)
          ChangeNotifierProvider.value(value: localeProvider!)
        else
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()..init()),
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, localeProvider, child) {
          return MaterialApp(
            onGenerateTitle: (context) =>
                AppLocalizations.of(context)!.appTitle,
            debugShowCheckedModeBanner: false,
            locale: localeProvider.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              FallbackCupertinoLocalizationsDelegate(),
            ],
            builder: (context, child) {
              return Directionality(
                textDirection: localeProvider.isRtl
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                child: child!,
              );
            },
            theme: ThemeData(
              primaryColor: AppColors.primaryColor,
              colorScheme: ColorScheme.fromSeed(
                seedColor: AppColors.primaryColor,
                brightness: Brightness.light,
              ),
              useMaterial3: true,
              appBarTheme: const AppBarTheme(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: AppColors.primaryColor, width: 2),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.red, width: 2),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
            home: const SplashScreen(),
            onGenerateRoute: (settings) {
              switch (settings.name) {
                case '/login':
                  return MaterialPageRoute(builder: (_) => const LoginScreen());
                case '/register':
                  return MaterialPageRoute(
                      builder: (_) => const RegisterScreen());
                case '/verify-otp':
                  final email = settings.arguments as String;
                  return MaterialPageRoute(
                    builder: (_) => OtpVerificationScreen(email: email),
                  );
                case '/forgot-password':
                  return MaterialPageRoute(
                      builder: (_) => const ForgotPasswordScreen());
                case '/home':
                  return MaterialPageRoute(builder: (_) => const HomeScreen());
                case '/child-detail':
                  final childId = settings.arguments as String;
                  return MaterialPageRoute(
                      builder: (_) => ChildDetailScreen(childId: childId));
                case '/location-history':
                  final args = settings.arguments as Map<String, String>;
                  return MaterialPageRoute(
                    builder: (_) => LocationHistoryScreen(
                      childId: args['childId']!,
                      childName: args['childName']!,
                    ),
                  );
                case '/alerts':
                  final childId = settings.arguments as String;
                  return MaterialPageRoute(
                      builder: (_) => AlertsScreen(childId: childId));
                case '/safe-zones':
                  final childId = settings.arguments as String?;
                  return MaterialPageRoute(
                      builder: (_) => SafeZonesScreen(childId: childId));
                case '/settings':
                  return MaterialPageRoute(
                      builder: (_) => const SettingsScreen());
                case '/about':
                  return MaterialPageRoute(builder: (_) => const AboutScreen());
                case '/add-child':
                  return MaterialPageRoute(
                      builder: (_) => const AddChildScreen());
                case '/edit-child':
                  final childId = settings.arguments as String;
                  return MaterialPageRoute(
                      builder: (_) => EditChildScreen(childId: childId));

                case '/add-safe-zone':
                  final childId = settings.arguments as String;
                  return MaterialPageRoute(
                      builder: (_) => AddSafeZoneScreen(childId: childId));
                case '/activity':
                  final args = settings.arguments as Map<String, String>;
                  return MaterialPageRoute(
                    builder: (_) => ActivityScreen(
                      childId: args['childId']!,
                      childName: args['childName']!,
                    ),
                  );
                case '/map':
                  final childId = settings.arguments as String?;
                  return MaterialPageRoute(
                    builder: (_) => MapScreen(childId: childId),
                  );
                case '/admin-login':
                  return MaterialPageRoute(
                      builder: (_) => const AdminLoginScreen());
                case '/admin-dashboard':
                  final authProvider =
                      Provider.of<AuthProvider>(context, listen: false);
                  return MaterialPageRoute(
                    builder: (_) => authProvider.isAdmin
                        ? const AdminDashboardScreen()
                        : const LoginScreen(),
                  );
                default:
                  return MaterialPageRoute(builder: (_) => const LoginScreen());
              }
            },
          );
        },
      ),
    );
  }
}
