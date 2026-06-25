// ═══════════════════════════════════════════════════════════════════
// FILE: main.dart
// PURPOSE: Eden app entry point. Firebase init, Riverpod, routing.
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
import 'theme/eden_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/chat_screen_v2.dart';
import 'screens/memory_vault_screen.dart';
import 'screens/settings_screen.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';

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
  final apiService = ref.watch(apiServiceProvider);
  return NotificationService(apiService);
});

// --- GoRouter Refresh Stream Listenable Helper ---
class GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _subscription;

  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((dynamic _) => notifyListeners());
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
    initialLocation: '/',
    refreshListenable: GoRouterRefreshStream(authService.authStateChanges),
    redirect: (context, state) {
      final isAuthenticated = authService.currentUser != null;

      final isSplash = state.matchedLocation == '/';
      final isAuth = state.matchedLocation == '/auth';

      if (!isAuthenticated) {
        // Force unauthenticated users to /auth unless they are already there or on the splash screen
        if (!isAuth && !isSplash) {
          return '/auth';
        }
      } else {
        // Authenticated users should not visit /auth
        if (isAuth) {
          return '/';
        }
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/auth',
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/chat',
        builder: (context, state) => const ChatScreenV2(),
      ),
      GoRoute(
        path: '/memories',
        builder: (context, state) => const MemoryVaultScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
});

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
    systemNavigationBarColor: EdenTheme.bgPrimary,
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
      router.go('/chat');
    };

    await notificationService.initialize();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Eden',
      debugShowCheckedModeBanner: false,
      theme: EdenTheme.dark(),
      routerConfig: router,
    );
  }
}
