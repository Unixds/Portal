import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'theme/portal_theme.dart';
import 'screens/onboarding/onboarding_flow.dart';
import 'screens/main_shell.dart';
import 'services/firebase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase initializeApp error: $e');
  }

  await PortalBackendService.instance.init();
  runApp(const PortalApp());
}

class PortalApp extends StatefulWidget {
  const PortalApp({super.key});

  @override
  State<PortalApp> createState() => _PortalAppState();
}

class _PortalAppState extends State<PortalApp> {
  late bool _isLoggedIn;

  @override
  void initState() {
    super.initState();
    _isLoggedIn = PortalBackendService.instance.currentUser != null;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Portal',
      debugShowCheckedModeBanner: false,
      theme: PortalTheme.themeData,
      home: _isLoggedIn
          ? MainShell(
              onSignOut: () {
                PortalBackendService.instance.signOut();
                setState(() => _isLoggedIn = false);
              },
            )
          : OnboardingFlowScreen(
              onOnboardingComplete: () {
                setState(() => _isLoggedIn = true);
              },
            ),
    );
  }
}
