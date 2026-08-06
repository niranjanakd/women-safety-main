import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../guarding/guarding_mode_screen.dart';
import './resources_screen.dart';
import './report_incident_screen.dart';
import './trusted_contacts_screen.dart';
import './profile_screen.dart';
import '../sos/emergency_protocol_screen.dart';

import '../../services/location_service.dart';

class UserMainShell extends StatefulWidget {
  const UserMainShell({super.key});

  @override
  State<UserMainShell> createState() => _UserMainShellState();
}

class _UserMainShellState extends State<UserMainShell> {
  int _currentIndex = 0;
  bool _isMale = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserPreferences();
    LocationService().startTracking(); // Start live tracking on app launch
  }

  Future<void> _loadUserPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final gender = prefs.getString('user_gender');
    setState(() {
      _isMale = (gender == 'male');
      if (_isMale) {
        _currentIndex = 0; // Starts at Trusted Contacts
      } else {
        _currentIndex = 0; // Starts at Guarding Mode
      }
      _isLoading = false;
    });
  }

  List<Widget> get _screens {
    if (_isMale) {
      return [
        const TrustedContactsScreen(),
        const ProfileScreen(),
      ];
    }
    return [
      const GuardingModeScreen(),
      const ResourcesScreen(),
      const SizedBox.shrink(), // SOS placeholder
      const ReportIncidentScreen(),
      const TrustedContactsScreen(),
      const ProfileScreen(),
    ];
  }

  List<BottomNavigationBarItem> get _navItems {
    if (_isMale) {
      return [
        _buildNavItem(icon: Icons.group_outlined, activeIcon: Icons.group, label: 'Trusted', index: 0),
        _buildNavItem(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Profile', index: 1),
      ];
    }
    return [
      _buildNavItem(icon: Icons.shield_outlined, activeIcon: Icons.shield, label: 'Guarding', index: 0),
      _buildNavItem(icon: Icons.menu_book_outlined, activeIcon: Icons.menu_book, label: 'Resources', index: 1),
      BottomNavigationBarItem(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: Color(0xFFEF4444),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.priority_high, color: Colors.white, size: 20),
        ),
        label: 'SOS',
      ),
      _buildNavItem(icon: Icons.assignment_outlined, activeIcon: Icons.assignment, label: 'Report', index: 3),
      _buildNavItem(icon: Icons.group_outlined, activeIcon: Icons.group, label: 'Trusted', index: 4),
      _buildNavItem(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Profile', index: 5),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: IndexedStack(
        index: (!_isMale && _currentIndex == 2) ? 0 : _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            if (!_isMale && index == 2) {
              _showSOSDialogue();
            } else {
              setState(() {
                _currentIndex = index;
              });
            }
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          elevation: 0,
          selectedItemColor: const Color(0xFF2563EB), // Figma Blue
          unselectedItemColor: const Color(0xFF94A3B8), // Figma Gray
          selectedLabelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            fontFamily: 'Inter',
          ),
          items: _navItems,
        ),
      ),
    );
  }

  BottomNavigationBarItem _buildNavItem({required IconData icon, required IconData activeIcon, required String label, required int index}) {
    bool isActive = _currentIndex == index;
    return BottomNavigationBarItem(
      icon: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFEFF6FF) : Colors.transparent, // Light blue splash for active
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          isActive ? activeIcon : icon,
          size: 24,
        ),
      ),
      label: label,
    );
  }

  void _showSOSDialogue() {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => const EmergencyProtocolScreen(),
      ),
    );
  }
}
