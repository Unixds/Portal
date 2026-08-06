import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/music_service.dart';

/// Settings -> "Разделы" (Sections) screen
class SectionsSettingsScreen extends StatefulWidget {
  const SectionsSettingsScreen({super.key});

  @override
  State<SectionsSettingsScreen> createState() => _SectionsSettingsScreenState();
}

class _SectionsSettingsScreenState extends State<SectionsSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final musicService = PortalMusicService.instance;

    return ListenableBuilder(
      listenable: musicService,
      builder: (context, _) {
        final isMusicEnabled = musicService.isMusicSectionEnabled;

        return Scaffold(
          backgroundColor: const Color(0xFF0F0F10),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0F0F10),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Разделы',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            children: [
              Text(
                'ВЫБОР РАЗДЕЛОВ ПРИЛОЖЕНИЯ',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white38),
              ),
              const SizedBox(height: 10),

              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8E2DE2).withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.music_note_rounded, color: Color(0xFF8E2DE2), size: 22),
                      ),
                      title: Text(
                        'Музыка',
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                      subtitle: Text(
                        'Раздел с вашей сохраненной музыкой и треками',
                        style: GoogleFonts.inter(fontSize: 13, color: Colors.white54),
                      ),
                      trailing: CupertinoSwitch(
                        activeColor: const Color(0xFF3390EC),
                        value: isMusicEnabled,
                        onChanged: (val) {
                          musicService.setMusicSectionEnabled(val);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Включите "Музыка", чтобы добавить отдельную вкладку "Музыка" в главное меню приложения.',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.white38, height: 1.4),
              ),
            ],
          ),
        );
      },
    );
  }
}
