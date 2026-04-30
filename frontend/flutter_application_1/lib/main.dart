import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'theme/app_colors.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
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
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gradientColors = AppColors.screenGradient(context);
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
                        color: Colors.white.withAlpha(18),
                        border: Border.all(
                          color: Colors.white.withAlpha((80 + (90 * glow)).toInt()),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFE57373).withAlpha(
                              (90 + (120 * glow)).toInt(),
                            ),
                            blurRadius: 24 + (16 * glow),
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.groups_rounded,
                        color: Colors.white,
                        size: 58,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'TeamMeeter',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Preparing your workspace...',
                      style: TextStyle(
                        color: Colors.white.withAlpha(210),
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
                        backgroundColor: Colors.white.withAlpha(35),
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
