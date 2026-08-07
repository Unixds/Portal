import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/portal_theme.dart';

/// Simple Contacts Tab Screen displaying empty contacts placeholder.
class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PortalTheme.bgCanvas,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 14),
            Text(
              'Контакты',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.2,
              ),
            ),
            const Expanded(
              child: Center(
                child: Text(
                  'У вас нет контактов',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF8E8E93),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
