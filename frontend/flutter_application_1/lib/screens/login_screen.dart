// Obrazovka na prihlásenie pomocou používateľského mena a hesla.
// Po úspešnom overení uloží token a používateľa presunie ďalej do aplikácie TeamMeeter.
// AI generated with manual refinements




import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
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
  late final GoogleSignIn _googleSignIn;
  late final Future<void> _googleInitFuture;

  @override
  // Tato funkcia pripravi uvodny stav obrazovky.
  // Spusta prve nacitanie dat a potrebne inicializacie.
  void initState() {
    super.initState();
    const webClientId = String.fromEnvironment(
      'GOOGLE_WEB_CLIENT_ID',
      defaultValue: '',
    );
    _googleSignIn = GoogleSignIn.instance;
    _googleInitFuture = _googleSignIn.initialize(
      serverClientId: webClientId.isEmpty ? null : webClientId,
    );
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
  // Tato funkcia uprace zdroje pred zatvorenim obrazovky.
  // Zastavi listenery, timery alebo controllery.
  void dispose() {
    _animController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Tato funkcia odosle alebo ulozi formular.
  // Pred odoslanim skontroluje vstupy a spracuje odpoved.
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

  Future<String?> _obtainGoogleIdToken() async {
    await _googleInitFuture;
    await _googleSignIn.signOut();
    Future<GoogleSignInAccount> authenticate() => _googleSignIn.authenticate(
          scopeHint: const ['email', 'profile'],
        );
    GoogleSignInAccount account = await authenticate();
    GoogleSignInAuthentication auth = account.authentication;
    String? idToken = auth.idToken;
    
    
    if (idToken == null || idToken.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return null;
      await _googleSignIn.signOut();
      account = await authenticate();
      auth = account.authentication;
      idToken = auth.idToken;
    }
    return idToken;
  }

  Future<void> _signInWithGoogle() async {
    try {
      final idToken = await _obtainGoogleIdToken();
      if (!mounted) return;
      if (idToken == null || idToken.isEmpty) {
        throw Exception(
          'Google ID token nebol získaný. Skontroluj GOOGLE_WEB_CLIENT_ID.',
        );
      }
      if (!mounted) return;
      await Provider.of<AuthProvider>(
        context,
        listen: false,
      ).loginWithGoogleIdToken(idToken);
    } on GoogleSignInException catch (e) {
      if (!mounted) return;
      String message = 'Google prihlásenie zlyhalo';
      if (e.code == GoogleSignInExceptionCode.clientConfigurationError) {
        message =
            'Google SSO nie je spravne nakonfigurovane (OAuth client/SHA-1/google-services).';
      } else if (e.code == GoogleSignInExceptionCode.canceled) {
        message = 'Google prihlasenie bolo zrusene.';
      }
      context.showLatestSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFF8B1A2C),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceAll('Exception: ', '').trim();
      context.showLatestSnackBar(
        SnackBar(
          content: Text(
            message.isEmpty ? 'Google prihlásenie zlyhalo' : message,
          ),
          backgroundColor: const Color(0xFF8B1A2C),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  // Tato funkcia sklada obrazovku z aktualnych dat.
  // Vrati widget strom, ktory uzivatel vidi na displeji.
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
                          Text(
                            'or',
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: authProvider.isLoading
                                ? null
                                : _signInWithGoogle,
                            child: Container(
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
                          ),
                          const SizedBox(height: 24),
                          
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
                          Text(
                            "Don't have an account?",
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
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


class TeamMeeterLogo extends StatelessWidget {
  final double size;
  const TeamMeeterLogo({super.key, this.size = 72});

  @override
  // Tato funkcia sklada obrazovku z aktualnych dat.
  // Vrati widget strom, ktory uzivatel vidi na displeji.
  Widget build(BuildContext context) {
    final ink = AppColors.isDark(context)
        ? Colors.white
        : const Color(0xFF1A1A1A);
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
              border: Border.all(color: ink, width: 2),
              borderRadius: BorderRadius.circular(size * 0.22),
            ),
            child: Icon(
              Icons.videocam_outlined,
              color: ink,
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
                color: ink,
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
                color: ink,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
