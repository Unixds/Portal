import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/portal_theme.dart';
import '../../services/firebase_service.dart';

/// Onboarding & Login Flow for Portal Messenger.
/// Supports 8-step Registration (with Cloud Password) and 2-step Login by @username & Cloud Password.
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
  String _phone = '';
  String _password = '';
  String _username = '';
  String _name = '';
  String _avatarUrl = 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=300&q=80';
  String _bio = '';

  // Login Form Data
  String _loginUsername = '';
  String _loginPassword = '';
  String? _loginError;

  // Validation States
  bool _isPhoneValid = false;
  bool _isPasswordValid = false;
  bool _isCheckingUsername = false;
  bool _isUsernameValid = false;
  String? _usernameError;
  bool _isSubmitting = false;

  final TextEditingController _phoneController = TextEditingController(text: '+7 ');
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
    _pageController.dispose();
    _phoneController.dispose();
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
    if (_currentStep < 7) {
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

  void _onPhoneChanged(String val) {
    if (!val.startsWith('+7 ')) {
      _phoneController.text = '+7 ';
      _phoneController.selection = TextSelection.fromPosition(
        TextPosition(offset: _phoneController.text.length),
      );
    }
    final digitsOnly = val.replaceAll(RegExp(r'\D'), '');
    setState(() {
      _phone = _phoneController.text;
      _isPhoneValid = digitsOnly.length >= 11;
    });
  }

  void _onPasswordChanged(String val) {
    setState(() {
      _password = val.trim();
      _isPasswordValid = _password.length >= 4;
    });
  }

  Future<void> _onUsernameChanged(String val) async {
    final raw = val.replaceAll('@', '').trim().toLowerCase();
    _username = raw;

    if (raw.length < 3) {
      setState(() {
        _isUsernameValid = false;
        _usernameError = raw.isEmpty ? null : 'Минимум 3 символа';
      });
      return;
    }

    setState(() {
      _isCheckingUsername = true;
      _usernameError = null;
    });

    final isFree = await PortalBackendService.instance.isUsernameAvailable(raw);

    setState(() {
      _isCheckingUsername = false;
      _isUsernameValid = isFree;
      if (!isFree) {
        _usernameError = 'Этот @username уже занят';
      }
    });
  }

  Future<void> _completeRegistration() async {
    setState(() => _isSubmitting = true);
    await PortalBackendService.instance.registerUser(
      phone: _phone.isEmpty ? '+7 (999) 000-00-00' : _phone,
      password: _password,
      username: _username.isEmpty ? 'user_${DateTime.now().millisecondsSinceEpoch % 10000}' : _username,
      name: _name.isEmpty ? 'Пользователь Portal' : _name,
      avatarUrl: _avatarUrl,
      bio: _bio.isEmpty ? 'Привет! Я в Portal ⚡' : _bio,
    );
    setState(() => _isSubmitting = false);
    widget.onOnboardingComplete();
  }

  Future<void> _performLogin() async {
    setState(() {
      _isSubmitting = true;
      _loginError = null;
    });

    final user = await PortalBackendService.instance.loginWithUsernameAndPassword(
      username: _loginUsername,
      password: _loginPassword,
    );

    setState(() => _isSubmitting = false);

    if (user != null) {
      widget.onOnboardingComplete();
    } else {
      setState(() {
        _loginError = 'Неверный @username или пароль';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background subtle ambient graphics
          Positioned(
            top: 40,
            left: 20,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.04),
              ),
            ),
          ),
          Positioned(
            top: 80,
            right: 40,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.03),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Top Nav Header
                if (_isLoginMode || (_currentStep > 0 && _currentStep < 7))
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
                            _buildScreen3PhoneInput(),
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
            Text('Введи свой @username', style: GoogleFonts.inter(fontSize: 14, color: Colors.white54)),
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
    }

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
          Text('Введи облачный пароль от аккаунта @$_loginUsername', style: GoogleFonts.inter(fontSize: 14, color: Colors.white54)),
          const SizedBox(height: 28),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _loginError != null ? PortalTheme.roseAccent : Colors.white.withOpacity(0.08)),
            ),
            child: TextField(
              controller: _loginPasswordController,
              obscureText: true,
              onChanged: (val) => setState(() {
                _loginPassword = val.trim();
                _loginError = null;
              }),
              style: GoogleFonts.inter(fontSize: 18, color: Colors.white),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Пароль',
                hintStyle: TextStyle(color: Colors.white30),
              ),
            ),
          ),
          if (_loginError != null) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(_loginError!, style: GoogleFonts.inter(fontSize: 13, color: PortalTheme.roseAccent)),
            ),
          ],
          const Spacer(),
          _buildWhitePrimaryButton(
            text: 'Войти',
            isEnabled: _loginPassword.isNotEmpty,
            isLoading: _isSubmitting,
            onTap: _performLogin,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // --- SCREEN 1: WELCOME ---
  Widget _buildScreen1Welcome() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        children: [
          const Spacer(),
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
            text: 'Продолжить с телефоном',
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

  // --- SCREEN 3: PHONE INPUT ---
  Widget _buildScreen3PhoneInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text(
            'Введи номер\nтелефона',
            style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white, height: 1.2),
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: const Row(
                  children: [
                    Text('🇷🇺', style: TextStyle(fontSize: 20)),
                    SizedBox(width: 6),
                    Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 18),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    onChanged: _onPhoneChanged,
                    style: GoogleFonts.inter(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: '+7 912 345-67-89',
                      hintStyle: TextStyle(color: Colors.white30),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Продолжая, ты соглашаешься получать уведомления об аккаунте.',
            style: GoogleFonts.inter(fontSize: 13, color: Colors.white38, height: 1.4),
          ),
          const Spacer(),
          _buildWhitePrimaryButton(
            text: 'Продолжить',
            isEnabled: _isPhoneValid,
            onTap: _nextPage,
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
                hintText: 'Создай пароль (мин. 4 символа)',
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

  // --- SCREEN 5: USERNAME INPUT ---
  Widget _buildScreen5UsernameInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text(
            'Имя пользователя',
            style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text('Другие смогут найти тебя по нему', style: GoogleFonts.inter(fontSize: 14, color: Colors.white54)),
          const SizedBox(height: 28),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E222D),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isUsernameValid
                    ? PortalTheme.emeraldAccent.withOpacity(0.6)
                    : Colors.white.withOpacity(0.08),
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
                    style: GoogleFonts.inter(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w500),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'username',
                      hintStyle: TextStyle(color: Colors.white30),
                    ),
                  ),
                ),
                if (_isCheckingUsername)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                  )
                else if (_isUsernameValid)
                  const Icon(Icons.check_circle_rounded, color: PortalTheme.emeraldAccent, size: 20),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _usernameError ?? '3–20 символов, латиница, цифры, _ и .',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: _usernameError != null ? PortalTheme.roseAccent : Colors.white38,
            ),
          ),
          const Spacer(),
          _buildWhitePrimaryButton(
            text: 'Продолжить',
            isEnabled: _isUsernameValid,
            onTap: _nextPage,
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _nextPage,
              child: Text(
                'Пропустить',
                style: GoogleFonts.inter(fontSize: 15, color: Colors.white54, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          const SizedBox(height: 12),
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
          Text('Введи имя', style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 6),
          Text('Оно будет отображаться у твоих собеседников', style: GoogleFonts.inter(fontSize: 14, color: Colors.white54)),
          const SizedBox(height: 28),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E222D),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: TextField(
              controller: _nameController,
              onChanged: (val) => setState(() => _name = val.trim()),
              style: GoogleFonts.inter(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w500),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text('О себе и Аватарка', style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 6),
          Text('Выбери или укажи ссылку на аватарку (видна всем)', style: GoogleFonts.inter(fontSize: 14, color: Colors.white54)),
          const SizedBox(height: 24),

          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 46,
                  backgroundColor: const Color(0xFF1E222D),
                  backgroundImage: NetworkImage(_avatarUrl),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.camera_alt_rounded, color: Colors.black, size: 16),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          Text('Выбери пресет аватарки:', style: GoogleFonts.inter(fontSize: 13, color: Colors.white54)),
          const SizedBox(height: 10),
          SizedBox(
            height: 56,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _avatarPresets.length,
              itemBuilder: (context, index) {
                final url = _avatarPresets[index];
                final isSelected = url == _avatarUrl;
                return GestureDetector(
                  onTap: () => setState(() {
                    _avatarUrl = url;
                    _customAvatarController.text = url;
                  }),
                  child: Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: EdgeInsets.all(isSelected ? 2 : 0),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
                    ),
                    child: CircleAvatar(
                      radius: 24,
                      backgroundImage: NetworkImage(url),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),
          Text('Или введи URL изображения:', style: GoogleFonts.inter(fontSize: 13, color: Colors.white54)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1E222D),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: TextField(
              controller: _customAvatarController,
              onChanged: (val) {
                if (val.trim().startsWith('http')) {
                  setState(() => _avatarUrl = val.trim());
                }
              },
              style: GoogleFonts.inter(fontSize: 14, color: Colors.white),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'https://...',
                hintStyle: TextStyle(color: Colors.white30),
              ),
            ),
          ),

          const SizedBox(height: 20),
          Text('О себе (Био):', style: GoogleFonts.inter(fontSize: 14, color: Colors.white54, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Container(
            height: 90,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E222D),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: TextField(
              controller: _bioController,
              maxLines: 2,
              onChanged: (val) => _bio = val.trim(),
              style: GoogleFonts.inter(fontSize: 15, color: Colors.white),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Расскажи о себе...',
                hintStyle: TextStyle(color: Colors.white30),
              ),
            ),
          ),

          const SizedBox(height: 28),
          _buildWhitePrimaryButton(
            text: 'Продолжить',
            onTap: _nextPage,
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: _nextPage,
              child: Text(
                'Пропустить',
                style: GoogleFonts.inter(fontSize: 15, color: Colors.white54, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // --- SCREEN 8: ALL SET ---
  Widget _buildScreen8Ready() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        children: [
          const Spacer(),
          Text(
            'Аккаунт создан',
            style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w600, color: Colors.white70),
          ),
          const Spacer(),
          _buildWhitePrimaryButton(
            text: 'Готово',
            isLoading: _isSubmitting,
            onTap: _completeRegistration,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildWhitePrimaryButton({
    required String text,
    required VoidCallback onTap,
    bool isEnabled = true,
    bool isLoading = false,
  }) {
    return GestureDetector(
      onTap: (isEnabled && !isLoading) ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          color: isEnabled ? Colors.white : const Color(0xFF1E222D),
          borderRadius: BorderRadius.circular(27),
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                )
              : Text(
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
