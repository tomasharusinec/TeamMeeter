// Tento súbor je vstupná časť celej aplikácie TeamMeeter.
// Spustí Flutter, inicializuje Firebase na pozadí, push službu a prvý viditeľný widget.
// This file was generated using AI (Gemini)




import 'dart:developer' as developer;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'theme/app_colors.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/firebase_observability.dart';
import 'services/push_navigation.dart';
import 'services/push_notification_service.dart';





final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'rootNavigator');

// Tato funkcia je vstupny bod celej appky.
// Zapne Firebase veci, pripravi notifikacie a potom spusti hlavny widget.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  
  
  
  PushNavigator.instance.attach(rootNavigatorKey);
  var navigatorObservers = <NavigatorObserver>[];
  try {
    await configureFirebaseObservability();
    navigatorObservers = [firebaseAnalyticsObserver];
  } catch (e, st) {
    developer.log(
      'main: configureFirebaseObservability zlyhalo',
      name: 'TeamMeeterFCM',
      error: e,
      stackTrace: st,
    );
  }
  try {
    await PushNotificationService.instance.ensureInitialized();
  } catch (e, st) {
    developer.log(
      'main: PushNotificationService.ensureInitialized zlyhalo',
      name: 'TeamMeeterFCM',
      error: e,
      stackTrace: st,
    );
  }
  runApp(MyApp(navigatorObservers: navigatorObservers));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.navigatorObservers = const []});

  final List<NavigatorObserver> navigatorObservers;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  // Tato funkcia po prvom vykresleni spracuje notifikaciu, ktorou sa appka otvorila.
  // Az potom povoli navigaciu na cielovu obrazovku z push spravy.
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await PushNotificationService.instance.consumeInitialMessage();
      } catch (e, st) {
        developer.log(
          'main: consumeInitialMessage zlyhalo',
          name: 'TeamMeeterFCM',
          error: e,
          stackTrace: st,
        );
      }
      PushNavigator.instance.notifyAppReady();
    });
  }

  @override
  // Tato funkcia zlozi koren aplikacie.
  // Nastavi providery, svetlu/tmavu temu a hlavny router aplikacie.
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) => AuthProvider()..loadSavedToken(),
        ),
        ChangeNotifierProvider(
          create: (_) => ThemeProvider()..loadSavedTheme(),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'TeamMeeter',
            debugShowCheckedModeBanner: false,
            navigatorKey: rootNavigatorKey,
            navigatorObservers: widget.navigatorObservers,
            themeMode: themeProvider.themeMode,
            theme: ThemeData(
              brightness: Brightness.light,
              scaffoldBackgroundColor: const Color(0xFFF6F3F3),
              colorScheme: const ColorScheme.light(
                primary: Color(0xFF8B1A2C),
                secondary: Color(0xFFAD2831),
                surface: Colors.white,
                onPrimary: Colors.white,
                onSecondary: Colors.white,
                onSurface: Color(0xFF1A1A1A),
              ),
              textTheme: GoogleFonts.interTextTheme(
                ThemeData.light().textTheme,
              ),
              dialogTheme: const DialogThemeData(
                backgroundColor: Color(0xFFF2ECEC),
              ),
              appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xFFF2ECEC),
                foregroundColor: Color(0xFF1A1A1A),
              ),
              useMaterial3: true,
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              scaffoldBackgroundColor: const Color(0xFF0D0D0D),
              colorScheme: const ColorScheme.dark(
                primary: Color(0xFF8B1A2C),
                secondary: Color(0xFFAD2831),
                surface: Color(0xFF1A0F0F),
                onPrimary: Colors.white,
                onSecondary: Colors.white,
                onSurface: Colors.white,
              ),
              textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
              dialogTheme: const DialogThemeData(
                backgroundColor: Color(0xFF1A0A0A),
              ),
              appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xFF1A0A0A),
                foregroundColor: Colors.white,
              ),
              useMaterial3: true,
            ),
            home: const AuthWrapper(),
          );
        },
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  // Tato funkcia rozhodne, ktoru uvodnu obrazovku ma uzivatel vidiet.
  // Podla stavu prihlasenia vrati loading, home alebo login screen.
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        if (authProvider.isInitializing) {
          return const _EpicLoadingScreen();
        }
        if (authProvider.isAuthenticated) {
          return const HomeScreen();
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}

class _EpicLoadingScreen extends StatefulWidget {
  const _EpicLoadingScreen();

  @override
  State<_EpicLoadingScreen> createState() => _EpicLoadingScreenState();
}

class _EpicLoadingScreenState extends State<_EpicLoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  // Tato funkcia pripravi animaciu pre uvodny loading.
  // Kontroler spusti pulzovanie loga, kym sa nacitava autentifikacia.
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  // Tato funkcia uvolni animacny kontroler.
  // Zabrani tomu, aby bezal aj po odchode z obrazovky.
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  // Tato funkcia vykresli loading obrazovku s animovanym logom.
  // Pouziva animacny stav na efekt zvacsenia a jemneho ziarenia.
  Widget build(BuildContext context) {
    final gradientColors = AppColors.screenGradient(context);
    final dark = AppColors.isDark(context);
    final heroIconColor = dark ? Colors.white : const Color(0xFF1A1A1A);
    final heroTitleStyle = TextStyle(
      color: heroIconColor,
      fontSize: 32,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    );
    final subtitleColor =
        dark ? Colors.white.withAlpha(210) : const Color(0xFF4A4A4A);
    return Scaffold(
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value;
          final glow = 0.3 + (t * 0.7);
          final scale = 0.96 + (t * 0.08);
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: gradientColors,
              ),
            ),
            child: Center(
              child: Transform.scale(
                scale: scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dark
                            ? Colors.white.withAlpha(18)
                            : const Color(0xFF8B1A2C).withAlpha(28),
                        border: Border.all(
                          color: dark
                              ? Colors.white.withAlpha(
                                  (80 + (90 * glow)).toInt(),
                                )
                              : const Color(0xFF8B1A2C).withAlpha(
                                  (100 + (80 * glow)).toInt(),
                                ),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFFE57373,
                            ).withAlpha((90 + (120 * glow)).toInt()),
                            blurRadius: 24 + (16 * glow),
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.groups_rounded,
                        color: heroIconColor,
                        size: 58,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('TeamMeeter', style: heroTitleStyle),
                    const SizedBox(height: 8),
                    Text(
                      'Preparing your workspace...',
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: 170,
                      child: LinearProgressIndicator(
                        value: 0.15 + (0.75 * t),
                        minHeight: 5,
                        borderRadius: BorderRadius.circular(999),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFFE57373),
                        ),
                        backgroundColor: dark
                            ? Colors.white.withAlpha(35)
                            : Colors.black.withAlpha(22),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
