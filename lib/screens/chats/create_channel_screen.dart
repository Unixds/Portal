import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/firebase_service.dart';
import 'chats_screen.dart'; // For buildAvatarImageProvider
import 'channel_detail_screen.dart';

/// 1-in-1 iOS Telegram Style Channel Creation Screen ("Создать канал")
class CreateChannelScreen extends StatefulWidget {
  const CreateChannelScreen({super.key});

  @override
  State<CreateChannelScreen> createState() => _CreateChannelScreenState();
}

class _CreateChannelScreenState extends State<CreateChannelScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _handleController = TextEditingController();

  String _avatarBase64 = '';
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _handleController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result != null && result.files.single.bytes != null) {
        final bytes = result.files.single.bytes!;
        setState(() {
          _avatarBase64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        });
      }
    } catch (_) {}
  }

  Future<void> _createChannel() async {
    final title = _titleController.text.trim();
    final desc = _descController.text.trim();
    var handle = _handleController.text.trim().replaceAll('@', '').toLowerCase();

    if (title.isEmpty) {
      setState(() => _errorMessage = 'Введите название канала');
      return;
    }

    if (handle.isEmpty) {
      handle = 'channel_${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}';
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final isFree = await PortalBackendService.instance.isChannelHandleAvailable(handle);
    if (!isFree) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Ссылка @$handle уже занята. Выберите другую.';
      });
      return;
    }

    final newChannel = await PortalBackendService.instance.createChannel(
      title: title,
      description: desc,
      handle: handle,
      avatarUrl: _avatarBase64,
    );

    if (!mounted) return;

    if (newChannel != null) {
      Navigator.pop(context); // Close CreateChannelScreen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChannelDetailScreen(channel: newChannel),
        ),
      );
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Ошибка создания канала. Попробуйте еще раз.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasTitle = _titleController.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top iOS Header Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Back Button: Dark circular container with left chevron
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1C1C1E),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.chevron_left_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),

                  // Center Title: "Создать канал"
                  Text(
                    'Создать канал',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),

                  // Right Action Button: "Далее"
                  GestureDetector(
                    onTap: _isLoading ? null : _createChannel,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF3390EC),
                              ),
                            )
                          : Text(
                              'Далее',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: hasTitle ? const Color(0xFF3390EC) : Colors.white38,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),

            // Form Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),

                    // Card 1: Circular Avatar + Channel Title Input
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          // Avatar Picker (Blue Camera Icon in Dark Blue Circle)
                          GestureDetector(
                            onTap: _pickAvatar,
                            child: _avatarBase64.isNotEmpty
                                ? CircleAvatar(
                                    radius: 28,
                                    backgroundImage: buildAvatarImageProvider(_avatarBase64),
                                  )
                                : Container(
                                    width: 56,
                                    height: 56,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF263244),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt_rounded,
                                      color: Color(0xFF3390EC),
                                      size: 26,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 16),

                          // Channel Name TextField
                          Expanded(
                            child: TextField(
                              controller: _titleController,
                              onChanged: (_) => setState(() {}),
                              style: GoogleFonts.inter(fontSize: 17, color: Colors.white),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                hintText: 'Название канала',
                                hintStyle: TextStyle(color: Colors.white38, fontSize: 17),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Card 2: Channel Description Input
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      child: TextField(
                        controller: _descController,
                        maxLines: 2,
                        style: GoogleFonts.inter(fontSize: 17, color: Colors.white),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText: 'Описание',
                          hintStyle: TextStyle(color: Colors.white38, fontSize: 17),
                        ),
                      ),
                    ),

                    // Subtitle under Card 2
                    Padding(
                      padding: const EdgeInsets.only(left: 16, top: 8),
                      child: Text(
                        'Можете указать дополнительное описание канала.',
                        style: GoogleFonts.inter(fontSize: 13, color: Colors.white38),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Card 3: Unique Link Handle Input (@handle)
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      child: TextField(
                        controller: _handleController,
                        style: GoogleFonts.inter(fontSize: 17, color: Colors.white),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          prefixText: '@ ',
                          prefixStyle: TextStyle(color: Color(0xFF3390EC), fontSize: 17, fontWeight: FontWeight.bold),
                          hintText: 'уникальная_ссылка (например: news_portal)',
                          hintStyle: TextStyle(color: Colors.white38, fontSize: 15),
                        ),
                      ),
                    ),

                    // Subtitle under Card 3
                    Padding(
                      padding: const EdgeInsets.only(left: 16, top: 8),
                      child: Text(
                        'Пользователи смогут находить ваш канал по этой публичной ссылке.',
                        style: GoogleFonts.inter(fontSize: 13, color: Colors.white38),
                      ),
                    ),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.redAccent.withOpacity(0.35)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
