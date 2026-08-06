import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SetupGuardingQuestionsScreen extends StatefulWidget {
  final VoidCallback onSetupComplete;

  const SetupGuardingQuestionsScreen({super.key, required this.onSetupComplete});

  @override
  State<SetupGuardingQuestionsScreen> createState() => _SetupGuardingQuestionsScreenState();
}

class _SetupGuardingQuestionsScreenState extends State<SetupGuardingQuestionsScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  
  // 5 Predefined questions for simplicity (and cognitive load reduction in emergencies)
  final List<String> _questions = [
    "What is your secret PIN code? (Numbers only)",
    "What is the name of your first pet?",
    "What city were you born in?",
    "What is your mother's maiden name?",
    "What is the name of your favorite childhood teacher?",
  ];

  final List<TextEditingController> _controllers = List.generate(5, (_) => TextEditingController());

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submitSetup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    // Offline Setup - Save to SharedPreferences locally
    final prefs = await SharedPreferences.getInstance();
    
    // Save each question and answer
    for (int i = 0; i < 5; i++) {
        await prefs.setString('guarding_q_$i', _questions[i]);
        await prefs.setString('guarding_a_$i', _controllers[i].text.trim());
    }

    await prefs.setBool('guarding_setup_complete', true);
    
    // Simulate a tiny delay for visual feedback
    await Future.delayed(const Duration(milliseconds: 500));
    
    setState(() => _isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Safety Verification Questions Saved Locally!'), backgroundColor: Colors.green),
      );
      widget.onSetupComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Setup Guarding Mode', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.security, size: 48, color: Colors.blue),
                const SizedBox(height: 16),
                Text(
                  "Set Your Safety Answers",
                  style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  "When you tap \"I'm Safe\" to disable Guarding Mode, you'll be asked ONE of these random questions. This prevents someone else from turning off your safety alert.",
                  style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade700, height: 1.5),
                ),
                const SizedBox(height: 32),
                
                ...List.generate(5, (index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Question ${index + 1}: ${_questions[index]}",
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _controllers[index],
                          decoration: InputDecoration(
                            hintText: "Your answer",
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please provide an answer';
                            }
                            return null;
                          },
                        )
                      ],
                    ),
                  );
                }),
                
                const SizedBox(height: 24),
                
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submitSetup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E50FF),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _isLoading 
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          "Save & Continue",
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
