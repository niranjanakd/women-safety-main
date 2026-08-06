import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../user/user_main_shell.dart';
import '../../services/background_guarding_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../police/police_dashboard_screen.dart';
import '../volunteer/volunteer_dashboard.dart';
import './pending_approval_screen.dart';
import './signup_page.dart';
import '../../services/api_service.dart';
import '../../services/location_service.dart';

enum UserRole { police, volunteer, user }

class UserRoleConfig {
  final String title;
  final Color primaryColor;
  final IconData icon;
  final String demoPhone; 
  final String demoPassword;

  UserRoleConfig({
    required this.title,
    required this.primaryColor,
    required this.icon,
    required this.demoPhone,
    required this.demoPassword,
  });

  factory UserRoleConfig.fromRole(UserRole role) {
    switch (role) {
      case UserRole.police:
        return UserRoleConfig(
          title: 'Police Login',
          primaryColor: const Color(0xFF2563EB),
          icon: Icons.verified_user,
          demoPhone: '1111111111',
          demoPassword: 'password123',
        );
      case UserRole.volunteer:
        return UserRoleConfig(
          title: 'Volunteer Login',
          primaryColor: const Color(0xFF9333EA),
          icon: Icons.shield,
          demoPhone: '2222222222',
          demoPassword: 'password123',
        );

      case UserRole.user:
        return UserRoleConfig(
          title: 'User Login',
          primaryColor: const Color(0xFFDB2777),
          icon: Icons.person,
          demoPhone: '9112223344',
          demoPassword: 'password123',
        );

    }
  }
}

class LoginPage extends StatefulWidget {
  final UserRole role;

  const LoginPage({super.key, required this.role});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phoneController = TextEditingController(); // Changed to phone
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  late UserRoleConfig config;

  @override
  void initState() {
    super.initState();
    config = UserRoleConfig.fromRole(widget.role);
    _phoneController.text = config.demoPhone;
    _passwordController.text = config.demoPassword;
  }

  Future<void> _handleLogin() async {
    final identifier = _phoneController.text.trim();
    final password = _passwordController.text.trim();

    if (identifier.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter all fields')));
      return;
    }

    setState(() => _isLoading = true);
    
    // Normalize phone: add +91 prefix for all roles (police, volunteer, user)
    String finalIdentifier = identifier;
    if (RegExp(r'^\d{10}$').hasMatch(identifier)) {
      finalIdentifier = '+91$identifier';
    } else if (RegExp(r'^91\d{10}$').hasMatch(identifier)) {
      finalIdentifier = '+$identifier';
    }

    // 1. Verify password and get user data + token immediately
    final loginResult = await ApiService.login(phone: finalIdentifier, password: password);
    
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!loginResult['success']) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${loginResult['message']}'), backgroundColor: Colors.red));
      return;
    }

    if (loginResult['requiresOtp'] == true) {
      _showOtpDialog(finalIdentifier, password);
      return;
    }

    if (loginResult['isPendingApproval'] == true) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const PendingApprovalScreen()),
      );
      return;
    }

    _navigateToDashboard(loginResult['data']);
  }

  Future<void> _showOtpDialog(String identifier, String password) async {
    final otpController = TextEditingController();
    bool isVerifying = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text('Enter OTP', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Please enter the 6-digit OTP sent to your phone number.', style: GoogleFonts.inter(color: Colors.black54)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: InputDecoration(
                      hintText: '000000',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isVerifying ? null : () => Navigator.pop(context),
                  child: Text('Cancel', style: GoogleFonts.inter(color: Colors.red)),
                ),
                ElevatedButton(
                  onPressed: isVerifying ? null : () async {
                    if (otpController.text.trim().length != 6) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid 6-digit OTP')));
                      return;
                    }
                    setStateDialog(() => isVerifying = true);
                    
                    final result = await ApiService.login(
                      phone: identifier,
                      password: password,
                      otp: otpController.text.trim(),
                    );
                    
                    setStateDialog(() => isVerifying = false);

                    if (result['success']) {
                      Navigator.pop(context); // Close dialog
                      
                      if (result['isPendingApproval'] == true) {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const PendingApprovalScreen()));
                      } else {
                        _navigateToDashboard(result['data']);
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'] ?? 'OTP verification failed')));
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: config.primaryColor),
                  child: isVerifying 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                    : const Text('Verify', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          }
        );
      }
    );
  }

  void _navigateToDashboard(Map<String, dynamic> userData) async {
    Widget nextScreen;
    switch (widget.role) {
      case UserRole.police: nextScreen = const PoliceDashboardScreen(); break;
      case UserRole.volunteer: nextScreen = VolunteerDashboardScreen(); break;
      case UserRole.user: nextScreen = const UserMainShell(); break;
    }

    // Start live tracking for ALL roles upon successful login
    LocationService().startTracking();

    if (widget.role == UserRole.user) {
      await initializeBackgroundService();
      if (await Permission.microphone.isGranted) {
        FlutterBackgroundService().startService();
      }
    }

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => nextScreen), (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, config.primaryColor.withOpacity(0.05)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                   const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, size: 20, color: Color(0xFF64748B)),
                      label: Text('Selection', style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 14)),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: config.primaryColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: config.primaryColor.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8)),
                      ],
                    ),
                    child: Icon(config.icon, color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    config.title,
                    style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your credentials to continue',
                    style: GoogleFonts.inter(fontSize: 16, color: const Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 40),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel(widget.role == UserRole.police ? 'Username' : 'Phone Number'),
                        _buildTextField(
                          controller: _phoneController,
                          hintText: widget.role == UserRole.police ? 'Enter username' : 'Enter phone number',
                          icon: widget.role == UserRole.police ? Icons.alternate_email : Icons.phone_outlined,
                          keyboardType: widget.role == UserRole.police ? TextInputType.text : TextInputType.phone,
                        ),
                        const SizedBox(height: 20),
                        _buildLabel('Password'),
                        _buildTextField(
                          controller: _passwordController,
                          hintText: 'Enter password',
                          icon: Icons.lock_outline,
                          obscureText: _obscurePassword,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off : Icons.visibility,
                              color: const Color(0xFF94A3B8),
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: config.primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: _isLoading 
                                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : Text('Login', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        if (widget.role != UserRole.police) ...[
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text("Don't have an account? ", style: GoogleFonts.inter(color: const Color(0xFF64748B))),
                              GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SignupPage(role: widget.role))),
                                child: Text('Sign Up', style: GoogleFonts.inter(color: config.primaryColor, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),
                  Text('Emergency? Call 112 immediately', style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF64748B))),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
      child: Text(text, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF475569))),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: Icon(icon, color: const Color(0xFF94A3B8)),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: config.primaryColor, width: 2)),
      ),
    );
  }
}
