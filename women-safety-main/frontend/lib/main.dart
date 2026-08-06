import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import './screens/auth/splash_route.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/background_guarding_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'dart:async';

import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize background service
  await initializeBackgroundService();
  
  // Auto-start if authenticated, user role is 'user', AND gender is 'female'
  final prefs = await SharedPreferences.getInstance();
  if (prefs.containsKey('auth_token')) {
    final role = prefs.getString('user_role');
    final gender = prefs.getString('user_gender');
    if ((role == 'user' || role == 'UserRole.user') && gender == 'female') {
      if (await Permission.microphone.isGranted) {
        FlutterBackgroundService().startService();
      }
    }
  }

  runApp(const SafeGuardApp());
}

// Overlay Entry Point
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const SosOverlay(),
    ),
  );
}

class SosOverlay extends StatefulWidget {
  const SosOverlay({super.key});

  @override
  State<SosOverlay> createState() => _SosOverlayState();
}

class _SosOverlayState extends State<SosOverlay> {
  int _seconds = 3;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_seconds > 1) {
        setState(() => _seconds--);
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, spreadRadius: 2),
          ],
          border: Border.all(color: Colors.red, width: 2),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "EMERGENCY SOS",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.red),
                  ),
                  Text(
                    "Activating in $_seconds seconds...",
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () {
                FlutterOverlayWindow.closeOverlay();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text("CANCEL", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

class SafeGuardApp extends StatelessWidget {
  const SafeGuardApp({super.key});
  

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SAFETYPIN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6366F1)),
        useMaterial3: true,
        textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme),
      ),
      home: const SplashRoute(),
    );
  }
}
