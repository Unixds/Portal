import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import '../../theme/portal_theme.dart';
import '../../services/firebase_service.dart';

/// Screen for editing current user's profile (Avatar, Name, @username, Bio).
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _usernameController;
  late TextEditingController _bioController;

  late String _avatarUrl;
  bool _isSaving = false;
  bool _isCheckingUsername = false;
  bool _isUsernameValid = true;
  String? _usernameError;

  @override
  void initState() {
    super.initState();
    final user = PortalBackendService.instance.currentUser;
    _nameController = TextEditingController(text: user?.name ?? '');
    _usernameController = TextEditingController(text: user?.username ?? '');
    _bioController = TextEditingController(text: user?.bio ?? '');
    _avatarUrl = user?.avatarUrl.isNotEmpty == true
        ? user!.avatarUrl
        : 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=300&q=80';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes != null) {
          final base64Str = base64Encode(file.bytes!);
          final ext = file.extension?.toLowerCase() ?? 'jpeg';
          setState(() {
            _avatarUrl = 'data:image/$ext;base64,$base64Str';
          });
        }
      }
    } catch (e) {
      debugPrint('Image picking error: $e');
    }
  }

  ImageProvider _buildAvatarImageProvider(String url) {
    if (url.startsWith('data:image')) {
      try {
        final base64Data = url.split(',').last;
        final bytes = base64Decode(base64Data);
        return MemoryImage(bytes);
      } catch (_) {}
    }
    return NetworkImage(url.isNotEmpty
        ? url
        : 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=300&q=80');
  }

  Future<void> _onUsernameChanged(String val) async {
    final raw = val.replaceAll('@', '').trim().toLowerCase();
    final currentUser = PortalBackendService.instance.currentUser;

    if (raw == currentUser?.username) {
      setState(() {
        _isUsernameValid = true;
        _usernameError = null;
      });
      return;
    }

    if (raw.length < 3) {
      setState(() {
        _isUsernameValid = false;
        _usernameError = 'Минимум 3 символа';
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

  Future<void> _saveProfile() async {
    if (_nameController.text.trim().isEmpty || !_isUsernameValid) return;

    setState(() => _isSaving = true);

    final success = await PortalBackendService.instance.updateUserProfile(
      name: _nameController.text.trim(),
      username: _usernameController.text.trim(),
      avatarUrl: _avatarUrl,
      bio: _bioController.text.trim(),
    );

    setState(() => _isSaving = false);

    if (mounted) {
      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Профиль успешно обновлен!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка сохранения профиля')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text('Редактировать', style: PortalTheme.titleHeader(fontSize: 18, color: Colors.white)),
                  TextButton(
                    onPressed: _isSaving ? null : _saveProfile,
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            'Готово',
                            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF3390EC)),
                          ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar Picker Button
                    Center(
                      child: GestureDetector(
                        onTap: _pickImageFromGallery,
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 52,
                              backgroundColor: const Color(0xFF1C1C1E),
                              backgroundImage: _buildAvatarImageProvider(_avatarUrl),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF3390EC),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                    Center(
                      child: TextButton.icon(
                        onPressed: _pickImageFromGallery,
                        icon: const Icon(Icons.photo_library_outlined, color: Color(0xFF3390EC), size: 18),
                        label: Text(
                          'Загрузить из галереи',
                          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500, color: const Color(0xFF3390EC)),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                    Text('Имя', style: GoogleFonts.inter(fontSize: 14, color: Colors.white54, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: TextField(
                        controller: _nameController,
                        style: GoogleFonts.inter(fontSize: 16, color: Colors.white),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Имя',
                          hintStyle: TextStyle(color: Colors.white30),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                    Text('Имя пользователя (@username)', style: GoogleFonts.inter(fontSize: 14, color: Colors.white54, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: !_isUsernameValid
                              ? PortalTheme.roseAccent
                              : Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text('@', style: GoogleFonts.inter(fontSize: 16, color: Colors.white54)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _usernameController,
                              onChanged: _onUsernameChanged,
                              style: GoogleFonts.inter(fontSize: 16, color: Colors.white),
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
                            ),
                        ],
                      ),
                    ),
                    if (_usernameError != null) ...[
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(_usernameError!, style: GoogleFonts.inter(fontSize: 13, color: PortalTheme.roseAccent)),
                      ),
                    ],

                    const SizedBox(height: 20),
                    Text('О себе (Био)', style: GoogleFonts.inter(fontSize: 14, color: Colors.white54, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Container(
                      height: 90,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: TextField(
                        controller: _bioController,
                        maxLines: 3,
                        style: GoogleFonts.inter(fontSize: 15, color: Colors.white),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Расскажи пару слов о себе...',
                          hintStyle: TextStyle(color: Colors.white30),
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
