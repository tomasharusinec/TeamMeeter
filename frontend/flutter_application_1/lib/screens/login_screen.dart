import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../providers/auth_provider.dart';
import '../utils/snackbar_utils.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_formKey.currentState!.validate()) {
      try {
        await Provider.of<AuthProvider>(
          context,
          listen: false,
        ).login(_usernameController.text, _passwordController.text);
      } catch (e) {
        if (mounted) {
          final cleaned = e.toString().replaceAll('Exception: ', '').trim();
          final message = (cleaned.isEmpty || cleaned == 'Exception')
              ? 'Wrong credentials'
              : cleaned;
          context.showLatestSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: const Color(0xFF8B1A2C),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final gradientColors = AppColors.screenGradient(context);
    final textColor = AppColors.textPrimary(context);
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: gradientColors,
            stops: [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Consumer<AuthProvider>(
                  builder: (context, authProvider, child) {
                    return Form(
                      key: _formKey,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 20),
                          // Logo
                          const TeamMeeterLogo(),
                          const SizedBox(height: 12),
                          Text(
                            'TeamMeeter',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 40),
                          Text(
                            'Sign in',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 24),
                          // Username field
                          _buildInputField(
                            controller: _usernameController,
                            hintText: 'Enter user name or email',
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Prosím zadajte používateľské meno';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          // Password field
                          _buildInputField(
                            controller: _passwordController,
                            hintText: 'Enter password',
                            isPassword: true,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Prosím zadajte heslo';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'or',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Google sign in placeholder
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(51),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Text(
                                'G',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF333333),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          // Sign in button
                          _buildButton(
                            text: 'Sign in',
                            onPressed: authProvider.isLoading ? null : _submit,
                            isLoading: authProvider.isLoading,
                          ),
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed: () {},
                            child: const Text(
                              'Forgot password?',
                              style: TextStyle(
                                color: Color(0xFFE57373),
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            "Don't have an account?",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildButton(
                            text: 'Register',
                            onPressed: () {
                              Navigator.of(context).push(
                                PageRouteBuilder(
                                  pageBuilder:
                                      (
                                        context,
                                        animation,
                                        secondaryAnimation,
                                      ) => const RegisterScreen(),
                                  transitionsBuilder:
                                      (
                                        context,
                                        animation,
                                        secondaryAnimation,
                                        child,
                                      ) {
                                        return FadeTransition(
                                          opacity: animation,
                                          child: child,
                                        );
                                      },
                                ),
                              );
                            },
                            small: true,
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hintText,
    bool isPassword = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword && !_isPasswordVisible,
      style: const TextStyle(color: Color(0xFF333333), fontSize: 14),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
        filled: true,
        fillColor: const Color(0xFFF5F0F0),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(25),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(25),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(25),
          borderSide: const BorderSide(color: Color(0xFF8B1A2C), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(25),
          borderSide: const BorderSide(color: Colors.red),
        ),
        errorStyle: const TextStyle(color: Color(0xFFE57373)),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                  color: Colors.grey.shade500,
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _isPasswordVisible = !_isPasswordVisible;
                  });
                },
              )
            : null,
      ),
      validator: validator,
    );
  }

  Widget _buildButton({
    required String text,
    VoidCallback? onPressed,
    bool isLoading = false,
    bool small = false,
  }) {
    return SizedBox(
      width: small ? 140 : double.infinity,
      height: small ? 38 : 44,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFF5F0F0),
          foregroundColor: const Color(0xFF333333),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
            side: BorderSide(color: Colors.grey.shade300),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF8B1A2C),
                ),
              )
            : Text(
                text,
                style: TextStyle(
                  fontSize: small ? 13 : 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
      ),
    );
  }
}

/// Reusable TeamMeeter logo widget matching the Figma calendar+camera design
class TeamMeeterLogo extends StatelessWidget {
  final double size;
  const TeamMeeterLogo({super.key, this.size = 72});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size + 6,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
              borderRadius: BorderRadius.circular(size * 0.22),
            ),
            child: Icon(
              Icons.videocam_outlined,
              color: Colors.white,
              size: size * 0.44,
            ),
          ),
          Positioned(
            top: 0,
            left: size * 0.22,
            child: Container(
              width: 3,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: size * 0.22,
            child: Container(
              width: 3,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
