import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import './role_selection_page.dart';
import '../user/user_main_shell.dart';
import '../volunteer/volunteer_dashboard.dart';
import '../police/police_dashboard_screen.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../../services/background_guarding_service.dart';

class SplashRoute extends StatefulWidget {
  const SplashRoute({super.key});

  @override
  State<SplashRoute> createState() => _SplashRouteState();
}

class _SplashRouteState extends State<SplashRoute> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    
    // Simulate a brief minimum splash sequence for UX
    await Future.delayed(const Duration(milliseconds: 800));
    
    if (token != null) {
      final role = prefs.getString('user_role');
      Widget nextScreen;
      
      if (role == 'volunteer' || role == 'UserRole.volunteer') {
        nextScreen = VolunteerDashboardScreen();
      } else if (role == 'authority' || role == 'police' || role == 'UserRole.police') {
        nextScreen = const PoliceDashboardScreen();
      } else {
        nextScreen = const UserMainShell();
        try {
          await initializeBackgroundService();
          if (await Permission.microphone.isGranted) {
            FlutterBackgroundService().startService();
          }
        } catch(e) { /* Service handles existing state silently */ }
      }
      
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => nextScreen));
    } else {
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const RoleSelectionPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF6366F1), 
      body: Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}
