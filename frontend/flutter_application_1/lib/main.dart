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
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
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
              textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
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
          final gradientColors = AppColors.screenGradient(context);
          return Scaffold(
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: gradientColors,
                ),
              ),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          );
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
