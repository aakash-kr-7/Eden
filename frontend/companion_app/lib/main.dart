// ═══════════════════════════════════════════════════════════════════
// FILE: main.dart
// PURPOSE: Eden app entry point. Firebase init, Riverpod, routing.
// RESPONSIBILITIES: Bootstrap core services, register routes, and mount the root app widget.
// NEVER: Contain screen-specific business rules or backend behavior changes.
// CONTEXT: Bootstraps the entire Flutter application.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'firebase_options.dart';
import 'theme/nocturne.dart';
import 'screens/boot_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/memory_vault_screen.dart';
import 'screens/settings_screen.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'components/app_background.dart';

// --- Riverpod Service Providers ---

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authStateProvider = StreamProvider<User?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges;
});

final apiServiceProvider = Provider<ApiService>((ref) {
  final authService = ref.watch(authServiceProvider);
  return ApiService(authService);
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService(ref.watch(apiServiceProvider));
  ref.onDispose(service.dispose);
  return service;
});

class AppRoute {
  AppRoute._();

  static const String boot = '/';
  static const String splash = '/splash';
  static const String auth = '/auth';
  static const String onboarding = '/onboarding';
  static const String chat = '/chat';
  static const String profile = '/chat/profile';
  static const String memory = '/chat/memory';
}

// --- GoRouter Refresh Stream Listenable Helper ---
class GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _subscription;

  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription =
        stream.asBroadcastStream().listen((dynamic _) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

// --- GoRouter Routing ---

final routerProvider = Provider<GoRouter>((ref) {
  final authService = ref.watch(authServiceProvider);

  return GoRouter(
    initialLocation: AppRoute.boot,
    refreshListenable: GoRouterRefreshStream(authService.authStateChanges),
    redirect: (context, state) {
      final isAuthenticated = authService.currentUser != null;

      final isSplash = state.matchedLocation == AppRoute.boot ||
          state.matchedLocation == AppRoute.splash;
      final isAuth = state.matchedLocation == AppRoute.auth;

      if (!isAuthenticated) {
        if (!isAuth && !isSplash) {
          return AppRoute.auth;
        }
      } else {
        if (isAuth) {
          return AppRoute.boot;
        }
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoute.boot,
        builder: (context, state) => const BootScreen(),
      ),
      GoRoute(
        path: AppRoute.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoute.auth,
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: AppRoute.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoute.chat,
        builder: (context, state) => const ChatScreen(),
        routes: [
          GoRoute(
            path: 'profile',
            pageBuilder: (context, state) =>
                _buildOverlayPage(state, const SettingsScreen()),
          ),
          GoRoute(
            path: 'memory',
            pageBuilder: (context, state) =>
                _buildOverlayPage(state, const MemoryVaultScreen()),
          ),
        ],
      ),
    ],
  );
});

CustomTransitionPage<void> _buildOverlayPage(
    GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    opaque: false,
    barrierColor: Colors.transparent,
    transitionDuration: Nocturne.durationStandard,
    reverseTransitionDuration: Nocturne.durationFast,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final fade = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      );
      final slide = Tween<Offset>(
        begin: const Offset(0, 0.012),
        end: Offset.zero,
      ).animate(fade);

      return FadeTransition(
        opacity: fade,
        child: SlideTransition(
          position: slide,
          child: child,
        ),
      );
    },
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Configure premium UI system overlay colors
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Nocturne.bgPrimary,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Preload google fonts
  unawaited(GoogleFonts.pendingFonts([
    GoogleFonts.plusJakartaSans(),
    GoogleFonts.cormorantGaramond(),
  ]));

  runApp(
    const ProviderScope(
      child: EdenApp(),
    ),
  );
}

class EdenApp extends ConsumerStatefulWidget {
  const EdenApp({super.key});

  @override
  ConsumerState<EdenApp> createState() => _EdenAppState();
}

class _EdenAppState extends ConsumerState<EdenApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initNotifications());
  }

  Future<void> _initNotifications() async {
    final notificationService = ref.read(notificationServiceProvider);

    // Configure background notification tap routing callback
    notificationService.onNavigateToChat = () {
      final router = ref.read(routerProvider);
      router.go(AppRoute.chat);
    };

    await notificationService.initialize();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Eden',
      debugShowCheckedModeBanner: false,
      theme: Nocturne.theme.copyWith(
        scaffoldBackgroundColor: Colors.transparent,
      ),
      routerConfig: router,
      builder: (context, child) {
        return Stack(
          children: [
            const AppBackground(),
            child!,
          ],
        );
      },
    );
  }
}
