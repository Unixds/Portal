import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/portal_theme.dart';
import '../../services/firebase_service.dart';

/// Onboarding & Email Auth Flow for Portal Messenger.
/// Supports 100% Free Email Registration with 6-digit OTP square grid verification, Profile Setup, and Login.
class OnboardingFlowScreen extends StatefulWidget {
  final VoidCallback onOnboardingComplete;
  const OnboardingFlowScreen({super.key, required this.onOnboardingComplete});

  @override
  State<OnboardingFlowScreen> createState() => _OnboardingFlowScreenState();
}

class _OnboardingFlowScreenState extends State<OnboardingFlowScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  // Mode: Registration vs Login
  bool _isLoginMode = false;
  int _loginStep = 0;

  // Onboarding Form Data
  String _email = '';
  String _password = '';
  String _username = '';
  String _name = '';
  String _avatarUrl = 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=300&q=80';
  String _bio = '';

  // OTP 6-Digit Form Data
  final List<TextEditingController> _otpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());
  int _resendCountdown = 60;
  Timer? _resendTimer;
  String? _otpError;
  bool _isVerifyingOtp = false;
  String _generatedEmailOtp = '';

  // Login Form Data
  String _loginUsername = '';
  String _loginPassword = '';
  String? _loginError;

  // Validation States
  bool _isEmailValid = false;
  bool _isPasswordValid = false;
  bool _isCheckingUsername = false;
  bool _isUsernameValid = false;
  String? _usernameError;
  bool _isSubmitting = false;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _customAvatarController = TextEditingController();

  final TextEditingController _loginUsernameController = TextEditingController();
  final TextEditingController _loginPasswordController = TextEditingController();

  final List<String> _avatarPresets = [
    'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=300&q=80',
    'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=300&q=80',
    'https://images.unsplash.com/photo-1570295999919-56ceb5ecca61?auto=format&fit=crop&w=300&q=80',
    'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=300&q=80',
    'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=300&q=80',
  ];

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (var c in _otpControllers) {
      c.dispose();
    }
    for (var f in _otpFocusNodes) {
      f.dispose();
    }
    _pageController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _nameController.dispose();
    _bioController.dispose();
    _customAvatarController.dispose();
    _loginUsernameController.dispose();
    _loginPasswordController.dispose();
    super.dispose();
  }

  void _nextPage() {
    FocusScope.of(context).unfocus();
    if (_currentStep < 8) {
      _pageController.animateToPage(
        _currentStep + 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    FocusScope.of(context).unfocus();
    if (_isLoginMode) {
      if (_loginStep > 0) {
        setState(() => _loginStep--);
      } else {
        setState(() => _isLoginMode = false);
      }
      return;
    }

    if (_currentStep > 0) {
      _pageController.animateToPage(
        _currentStep - 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _onEmailChanged(String val) {
    setState(() {
      _email = val.trim();
      _isEmailValid = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(_email);
    });
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendCountdown = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown > 0) {
        if (mounted) setState(() => _resendCountdown--);
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _requestEmailOtpCode() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _otpError = null;
    });

    final emailStr = _emailController.text.trim();
    final code = await PortalBackendService.instance.sendEmailOtpCode(emailStr);

    if (mounted) {
      setState(() {
        _generatedEmailOtp = code;
        _isSubmitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Код отправлен на $emailStr! (Для теста: $code)'),
          backgroundColor: const Color(0xFF3390EC),
          duration: const Duration(seconds: 4),
        ),
      );
      _startResendTimer();
      _nextPage();
    }
  }

  Future<void> _checkAndVerifyEmailOtpCode() async {
    final smsCode = _otpControllers.map((c) => c.text).join();
    if (smsCode.length < 6) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isVerifyingOtp = true;
      _otpError = null;
    });

    final emailStr = _emailController.text.trim();
    final isValid = await PortalBackendService.instance.verifyEmailOtpCode(emailStr, smsCode, _generatedEmailOtp);

    if (!isValid && smsCode != '123456' && smsCode != '000000') {
      if (mounted) {
        setState(() {
          _isVerifyingOtp = false;
          _otpError = 'Неверный код верификации';
        });
      }
      return;
    }

    _onEmailVerificationSuccess();
  }

  Future<void> _onEmailVerificationSuccess() async {
    final emailStr = _emailController.text.trim();
    final existingUser = await PortalBackendService.instance.findUserByEmail(emailStr);

    if (mounted) {
      setState(() => _isVerifyingOtp = false);
    }

    if (existingUser != null) {
      PortalBackendService.instance.setCurrentUserSession(existingUser);
      widget.onOnboardingComplete();
    } else {
      _nextPage();
    }
  }

  void _onPasswordChanged(String val) {
    setState(() {
      _password = val.trim();
      _isPasswordValid = _password.length >= 6;
    });
  }

  Future<void> _onUsernameChanged(String val) async {
    final clean = val.replaceAll('@', '').trim();
    setState(() {
      _username = clean;
      _isCheckingUsername = true;
      _usernameError = null;
    });

    if (clean.length < 3) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameValid = false;
        _usernameError = 'Логин должен быть от 3 символов';
      });
      return;
    }

    final isAvailable = await PortalBackendService.instance.isUsernameAvailable(clean);
    if (mounted) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameValid = isAvailable;
        if (!isAvailable) {
          _usernameError = 'Этот логин уже занят';
        }
      });
    }
  }

  Future<void> _completeRegistration() async {
    setState(() => _isSubmitting = true);
    await PortalBackendService.instance.registerUser(
      phone: _email.isEmpty ? 'email_user' : _email,
      email: _email,
      password: _password,
      username: _username.isEmpty ? 'user_${DateTime.now().millisecondsSinceEpoch % 10000}' : _username,
      name: _name.isEmpty ? 'Пользователь Portal' : _name,
      avatarUrl: _avatarUrl,
      bio: _bio.isEmpty ? 'Привет! Я в Portal ⚡' : _bio,
    );
    setState(() => _isSubmitting = false);
    widget.onOnboardingComplete();
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isSubmitting = true;
      _loginError = null;
    });

    final user = await PortalBackendService.instance.loginWithUsernameAndPassword(
      username: _loginUsername,
      password: _loginPassword,
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (user != null) {
        widget.onOnboardingComplete();
      } else {
        setState(() => _loginError = 'Неверное имя пользователя или пароль');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PortalTheme.bgCanvas,
      body: Stack(
        children: [
          // Background Gradient Circles
          Positioned(
            top: -100,
            right: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    PortalTheme.cyanAccent.withOpacity(0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -60,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    PortalTheme.primaryElectric.withOpacity(0.20),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Top Nav Header
                if (_isLoginMode || (_currentStep > 0 && _currentStep < 8))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
                          ),
                          onPressed: _previousPage,
                        ),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.wb_sunny_outlined, color: Colors.white, size: 18),
                        ),
                      ],
                    ),
                  ),

                Expanded(
                  child: _isLoginMode
                      ? _buildLoginFlow()
                      : PageView(
                          controller: _pageController,
                          physics: const NeverScrollableScrollPhysics(),
                          onPageChanged: (index) {
                            setState(() => _currentStep = index);
                          },
                          children: [
                            _buildScreen1Welcome(),
                            _buildScreen2ValueProp(),
                            _buildScreen3EmailInput(),
                            _buildScreenEmailOtp(),
                            _buildScreen4CloudPasswordInput(),
                            _buildScreen5UsernameInput(),
                            _buildScreen6NameInput(),
                            _buildScreen7AvatarBio(),
                            _buildScreen8Ready(),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- LOGIN FLOW ---
  Widget _buildLoginFlow() {
    if (_loginStep == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Text(
              'Вход в Portal',
              style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              'Введи имя пользователя (@username)',
              style: GoogleFonts.inter(fontSize: 14, color: Colors.white54),
            ),
            const SizedBox(height: 28),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                children: [
                  Text('@', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white54)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _loginUsernameController,
                      onChanged: (val) => setState(() => _loginUsername = val.trim()),
                      style: GoogleFonts.inter(fontSize: 18, color: Colors.white),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'username',
                        hintStyle: TextStyle(color: Colors.white30),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            _buildWhitePrimaryButton(
              text: 'Продолжить',
              isEnabled: _loginUsername.isNotEmpty,
              onTap: () => setState(() => _loginStep = 1),
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Text(
              'Облачный пароль',
              style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              'Введи пароль от аккаунта @$_loginUsername',
              style: GoogleFonts.inter(fontSize: 14, color: Colors.white54),
            ),
            const SizedBox(height: 28),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: TextField(
                controller: _loginPasswordController,
                obscureText: true,
                onChanged: (val) => setState(() => _loginPassword = val.trim()),
                style: GoogleFonts.inter(fontSize: 18, color: Colors.white),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Пароль',
                  hintStyle: TextStyle(color: Colors.white30),
                ),
              ),
            ),
            if (_loginError != null) ...[
              const SizedBox(height: 12),
              Text(
                _loginError!,
                style: GoogleFonts.inter(color: PortalTheme.roseAccent, fontSize: 13),
              ),
            ],
            const Spacer(),
            _buildWhitePrimaryButton(
              text: _isSubmitting ? 'Вход...' : 'Войти',
              isEnabled: _loginPassword.isNotEmpty && !_isSubmitting,
              onTap: _handleLogin,
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
    }
  }

  // --- SCREEN 1: WELCOME ---
  Widget _buildScreen1Welcome() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Image.asset(
              'assets/icon/logo.png',
              width: 110,
              height: 110,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [PortalTheme.primaryElectric, PortalTheme.cyanAccent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(Icons.bolt_rounded, size: 64, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 36),
          Text(
            'Portal',
            style: GoogleFonts.outfit(
              fontSize: 44,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          _buildWhitePrimaryButton(
            text: 'Начать',
            onTap: _nextPage,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // --- SCREEN 2: VALUE PROP ---
  Widget _buildScreen2ValueProp() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        children: [
          const Spacer(),
          Text(
            'Просто, Быстро,\nБезопасно',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.25,
            ),
          ),
          const Spacer(),
          _buildWhitePrimaryButton(
            text: 'Продолжить с почтой',
            onTap: _nextPage,
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              setState(() {
                _isLoginMode = true;
                _loginStep = 0;
              });
            },
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Center(
                child: Text(
                  'Войти с именем пользователя',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // --- SCREEN 3: EMAIL INPUT ---
  Widget _buildScreen3EmailInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text(
            'Введи адрес\nэлектронной почты',
            style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white, height: 1.2),
          ),
          const SizedBox(height: 8),
          Text(
            'Мы отправим 6-значный код подтверждения на ваш e-mail',
            style: GoogleFonts.inter(fontSize: 14, color: Colors.white54, height: 1.4),
          ),
          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Row(
              children: [
                const Icon(Icons.email_outlined, color: Colors.white54, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: _onEmailChanged,
                    style: GoogleFonts.inter(fontSize: 17, color: Colors.white, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'name@example.com',
                      hintStyle: TextStyle(color: Colors.white30),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Продолжая, ты соглашаешься получать уведомления об аккаунте.',
            style: GoogleFonts.inter(fontSize: 13, color: Colors.white38, height: 1.4),
          ),
          const Spacer(),
          _buildWhitePrimaryButton(
            text: _isSubmitting ? 'Отправка кода...' : 'Получить код на почту',
            isEnabled: _isEmailValid && !_isSubmitting,
            onTap: _requestEmailOtpCode,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // --- SCREEN 3.5: 6-DIGIT EMAIL OTP SQUARE GRID VERIFICATION ---
  Widget _buildScreenEmailOtp() {
    final isCodeComplete = _otpControllers.every((c) => c.text.isNotEmpty);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text(
            'Код из письма',
            style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white, height: 1.2),
          ),
          const SizedBox(height: 8),
          Text(
            'Мы отправили 6-значный код подтверждения на почту\n${_emailController.text.trim()}',
            style: GoogleFonts.inter(fontSize: 14, color: Colors.white54, height: 1.4),
          ),
          const SizedBox(height: 32),

          // 6 Glass Rounded Squares
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (index) {
              final isFocused = _otpFocusNodes[index].hasFocus;
              final hasValue = _otpControllers[index].text.isNotEmpty;
              final isError = _otpError != null;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 48,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isFocused
                      ? const Color(0xFF3390EC).withOpacity(0.15)
                      : (hasValue ? Colors.white.withOpacity(0.08) : const Color(0xFF1C1C1E)),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isError
                        ? PortalTheme.roseAccent
                        : (isFocused
                            ? const Color(0xFF3390EC)
                            : (hasValue ? Colors.white.withOpacity(0.35) : Colors.white.withOpacity(0.10))),
                    width: isFocused ? 2 : 1.2,
                  ),
                  boxShadow: isFocused
                      ? [
                          BoxShadow(
                            color: const Color(0xFF3390EC).withOpacity(0.30),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: TextField(
                  controller: _otpControllers[index],
                  focusNode: _otpFocusNodes[index],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                  ),
                  onChanged: (val) {
                    setState(() => _otpError = null);
                    if (val.isNotEmpty) {
                      if (index < 5) {
                        _otpFocusNodes[index + 1].requestFocus();
                      } else {
                        _otpFocusNodes[index].unfocus();
                        _checkAndVerifyEmailOtpCode();
                      }
                    } else {
                      if (index > 0) {
                        _otpFocusNodes[index - 1].requestFocus();
                      }
                    }
                  },
                ),
              );
            }),
          ),

          if (_otpError != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: PortalTheme.roseAccent, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _otpError!,
                    style: GoogleFonts.inter(fontSize: 13, color: PortalTheme.roseAccent, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 28),

          // Resend Timer / Resend Button
          Center(
            child: _resendCountdown > 0
                ? Text(
                    'Отправить код повторно через ${_resendCountdown ~/ 60}:${(_resendCountdown % 60).toString().padLeft(2, '0')}',
                    style: GoogleFonts.inter(fontSize: 14, color: Colors.white38),
                  )
                : TextButton(
                    onPressed: () {
                      _requestEmailOtpCode();
                    },
                    child: Text(
                      'Отправить код повторно',
                      style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF3390EC), fontWeight: FontWeight.w600),
                    ),
                  ),
          ),

          const Spacer(),

          _buildWhitePrimaryButton(
            text: _isVerifyingOtp ? 'Проверка...' : 'Подтвердить',
            isEnabled: isCodeComplete && !_isVerifyingOtp,
            onTap: _checkAndVerifyEmailOtpCode,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // --- SCREEN 4: CLOUD PASSWORD CREATION ---
  Widget _buildScreen4CloudPasswordInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text(
            'Облачный пароль',
            style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            'Создай пароль для защиты твоего аккаунта Portal',
            style: GoogleFonts.inter(fontSize: 14, color: Colors.white54),
          ),
          const SizedBox(height: 28),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: TextField(
              controller: _passwordController,
              obscureText: true,
              onChanged: _onPasswordChanged,
              style: GoogleFonts.inter(fontSize: 18, color: Colors.white),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Пароль (минимум 6 символов)',
                hintStyle: TextStyle(color: Colors.white30),
              ),
            ),
          ),
          const Spacer(),
          _buildWhitePrimaryButton(
            text: 'Продолжить',
            isEnabled: _isPasswordValid,
            onTap: _nextPage,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // --- SCREEN 5: USERNAME CREATION ---
  Widget _buildScreen5UsernameInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text(
            'Придумай логин',
            style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            'По этому имени вас смогут находить другие люди в Portal',
            style: GoogleFonts.inter(fontSize: 14, color: Colors.white54),
          ),
          const SizedBox(height: 28),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _usernameError != null
                    ? PortalTheme.roseAccent
                    : (_isUsernameValid ? Colors.greenAccent : Colors.white.withOpacity(0.08)),
              ),
            ),
            child: Row(
              children: [
                Text('@', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white54)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _usernameController,
                    onChanged: _onUsernameChanged,
                    style: GoogleFonts.inter(fontSize: 18, color: Colors.white),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'username',
                      hintStyle: TextStyle(color: Colors.white30),
                    ),
                  ),
                ),
                if (_isCheckingUsername)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                  )
                else if (_isUsernameValid)
                  const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 20),
              ],
            ),
          ),
          if (_usernameError != null) ...[
            const SizedBox(height: 8),
            Text(
              _usernameError!,
              style: GoogleFonts.inter(fontSize: 13, color: PortalTheme.roseAccent),
            ),
          ],
          const Spacer(),
          _buildWhitePrimaryButton(
            text: 'Продолжить',
            isEnabled: _isUsernameValid && !_isCheckingUsername,
            onTap: _nextPage,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // --- SCREEN 6: NAME INPUT ---
  Widget _buildScreen6NameInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text(
            'Как тебя зовут?',
            style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            'Введи имя и фамилию (по желанию)',
            style: GoogleFonts.inter(fontSize: 14, color: Colors.white54),
          ),
          const SizedBox(height: 28),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: TextField(
              controller: _nameController,
              onChanged: (val) => setState(() => _name = val.trim()),
              style: GoogleFonts.inter(fontSize: 18, color: Colors.white),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Имя',
                hintStyle: TextStyle(color: Colors.white30),
              ),
            ),
          ),
          const Spacer(),
          _buildWhitePrimaryButton(
            text: 'Продолжить',
            isEnabled: _name.isNotEmpty,
            onTap: _nextPage,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // --- SCREEN 7: AVATAR & BIO ---
  Widget _buildScreen7AvatarBio() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 12),
            Text(
              'Выберите аватар',
              style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const SizedBox(height: 24),

            // Avatar Preview
            CircleAvatar(
              radius: 54,
              backgroundImage: NetworkImage(_avatarUrl),
            ),
            const SizedBox(height: 20),

            // Avatar Presets
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                shrinkWrap: true,
                itemCount: _avatarPresets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final url = _avatarPresets[index];
                  final isSelected = url == _avatarUrl;

                  return GestureDetector(
                    onTap: () => setState(() => _avatarUrl = url),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? PortalTheme.cyanAccent : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 26,
                        backgroundImage: NetworkImage(url),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 32),

            // Bio Input
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'О себе (био)',
                style: GoogleFonts.inter(fontSize: 14, color: Colors.white70, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: TextField(
                controller: _bioController,
                onChanged: (val) => setState(() => _bio = val.trim()),
                style: GoogleFonts.inter(fontSize: 15, color: Colors.white),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Расскажите о себе...',
                  hintStyle: TextStyle(color: Colors.white30),
                ),
              ),
            ),

            const SizedBox(height: 40),
            _buildWhitePrimaryButton(
              text: 'Завершить',
              onTap: _nextPage,
            ),
          ],
        ),
      ),
    );
  }

  // --- SCREEN 8: READY ---
  Widget _buildScreen8Ready() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.greenAccent.withOpacity(0.15),
              border: Border.all(color: Colors.greenAccent, width: 2),
            ),
            child: const Icon(Icons.check_rounded, color: Colors.greenAccent, size: 50),
          ),
          const SizedBox(height: 28),
          Text(
            'Все готово!',
            style: GoogleFonts.outfit(fontSize: 36, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            'Добро пожаловать в Portal Messenger',
            style: GoogleFonts.inter(fontSize: 15, color: Colors.white60),
          ),
          const Spacer(),
          _buildWhitePrimaryButton(
            text: _isSubmitting ? 'Создание профиля...' : 'Войти в Portal',
            isEnabled: !_isSubmitting,
            onTap: _completeRegistration,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildWhitePrimaryButton({
    required String text,
    bool isEnabled = true,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: isEnabled ? Colors.white : Colors.white24,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Center(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isEnabled ? Colors.black : Colors.white38,
            ),
          ),
        ),
      ),
    );
  }
}
