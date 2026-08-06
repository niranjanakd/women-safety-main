import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/api_service.dart';
import './login_page.dart';
import '../user/user_main_shell.dart';
import '../../services/background_guarding_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../police/police_dashboard_screen.dart';
import '../volunteer/volunteer_dashboard.dart';
import './pending_approval_screen.dart';

class SignupPage extends StatefulWidget {
  final UserRole role;

  const SignupPage({super.key, required this.role});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  final _ageController = TextEditingController();
  final _addressController = TextEditingController();
  String? _selectedGender;

  final _permanentAddressController = TextEditingController();
  final _currentAddressController = TextEditingController();
  final _aadhaarController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  late final Color _primaryColor;

  @override
  void initState() {
    super.initState();
    switch (widget.role) {
      case UserRole.police:
        _primaryColor = const Color(0xFF2563EB);
        break;
      case UserRole.volunteer:
        _primaryColor = const Color(0xFF9333EA);
        break;
      case UserRole.user:
        _primaryColor = const Color(0xFFDB2777);
        break;
    }
  }

  Future<void> _handleSignup() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text.trim();
    final gender = _selectedGender;

    if (name.isEmpty ||
        phone.isEmpty ||
        password.isEmpty ||
        gender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Name, Phone, Password, and Gender are required',
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final String fullPhone = phone.startsWith('+') ? phone : '+91$phone';

    Map<String, dynamic> userData = {
      'name': name,
      'email': _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
      'phone': fullPhone,
      'password': password,
      'age': _ageController.text.trim().isNotEmpty ? int.tryParse(_ageController.text.trim()) : null,
      'gender': gender,
      'address': _addressController.text.trim(),
      'role': widget.role.name,
    };

    if (widget.role == UserRole.volunteer) {
      userData.addAll({
        'permanentAddress': _permanentAddressController.text.trim(),
        'currentAddressString': _currentAddressController.text.trim(),
        'aadhaarNumber': _aadhaarController.text.trim(),
      });
    }

    final result = await ApiService.sendOtp(phone: fullPhone);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success']) {
      _showOtpDialog(userData, fullPhone);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${result['message']}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showOtpDialog(Map<String, dynamic> userData, String phone) async {
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
              title: Text('Verify Phone', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
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
                    
                    final result = await ApiService.register(
                      userData: userData,
                      otp: otpController.text.trim(),
                    );
                    
                    setStateDialog(() => isVerifying = false);

                    if (result['success']) {
                      Navigator.pop(context); // Close dialog
                      _handleRegistrationSuccess(result);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'] ?? 'OTP verification failed', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red));
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
                  child: isVerifying 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                    : const Text('Verify & Register', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          }
        );
      }
    );
  }

  Future<void> _handleRegistrationSuccess(Map<String, dynamic> result) async {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Registration Success!')));

    Widget nextScreen;
    switch (widget.role) {
      case UserRole.police:
        nextScreen = const PoliceDashboardScreen();
        break;
      case UserRole.volunteer:
        nextScreen = VolunteerDashboardScreen();
        break;
      case UserRole.user:
        nextScreen = const UserMainShell();
        break;
    }

    if (widget.role == UserRole.user) {
      await initializeBackgroundService();
      if (await Permission.microphone.isGranted) {
        FlutterBackgroundService().startService();
      }
    }

    if (result['isPendingApproval'] == true) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const PendingApprovalScreen()),
        (route) => false,
      );
      return;
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => nextScreen),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              const SizedBox(height: 20),
              Text(
                'Create Account',
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter details to verify your account',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 40),
                _buildTextField(
                  controller: _nameController,
                  hintText: 'Full Name',
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _emailController,
                  hintText: 'Email Address (Optional)',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _phoneController,
                  hintText: 'Phone Number',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _ageController,
                  hintText: 'Age / DOB',
                  icon: Icons.calendar_today_outlined,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                _buildDropdownField('Gender', [
                  'male',
                  'female',
                  'other',
                ], Icons.wc_outlined),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _addressController,
                  hintText: 'Address',
                  icon: Icons.location_on_outlined,
                ),
                const SizedBox(height: 16),

                if (widget.role == UserRole.volunteer) ...[
                  _buildTextField(
                    controller: _permanentAddressController,
                    hintText: 'Permanent Address',
                    icon: Icons.home_outlined,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _currentAddressController,
                    hintText: 'Current Residence Address',
                    icon: Icons.location_city_outlined,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _aadhaarController,
                    hintText: '12-digit Aadhaar Number',
                    icon: Icons.badge_outlined,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                ],
                _buildTextField(
                  controller: _passwordController,
                  hintText: 'Password',
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
                  onPressed: _isLoading ? null : _handleSignup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Sign Up',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already have an account? ',
                      style: GoogleFonts.inter(color: const Color(0xFF64748B)),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Text(
                        'Login',
                        style: GoogleFonts.inter(
                          color: _primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
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
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: _primaryColor, width: 2),
        ),
      ),
    );
  }

  Widget _buildDropdownField(
    String hintText,
    List<String> items,
    IconData icon,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: _selectedGender,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: Icon(icon, color: const Color(0xFF94A3B8)),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: _primaryColor, width: 2),
        ),
      ),
      items: items.map((String value) {
        return DropdownMenuItem<String>(
          value: value,
          child: Text(value[0].toUpperCase() + value.substring(1)),
        );
      }).toList(),
      onChanged: (newValue) {
        setState(() {
          _selectedGender = newValue;
        });
      },
    );
  }
}
