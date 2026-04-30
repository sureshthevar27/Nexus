import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'dashboard_screen.dart';
import '../theme.dart'; // Ensure theme is imported for Color constants

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  // LOGIC PRESERVED: Controllers and state variables untouched [cite: 2, 3, 4]
  final _abhaController = TextEditingController(text: '1234567890123456');
  final _nameController = TextEditingController(text: 'Vishwavel S');
  final _dobController = TextEditingController(text: '1985-03-15');
  final _otpController = TextEditingController();

  bool _isLoading = false;
  bool _otpRequired = false;
  String _errorMessage = '';

  // LOGIC PRESERVED: API calls and navigation untouched [cite: 5-15]
  Future<void> _linkRecord() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final response = await ApiService.linkRecord(
        _abhaController.text.trim(),
        _nameController.text.trim(),
        _dobController.text.trim(),
      );
      if (response['match'] == true && response['otp_required'] == true) {
        setState(() {
          _otpRequired = true;
          _otpController.text = '123456'; // For hackathon demo
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  Future<void> _verifyOtp() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final response = await ApiService.verifyOtp(
        _abhaController.text.trim(),
        _otpController.text.trim(),
      );
      if (response['access_token'] != null) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => DashboardScreen(abhaId: _abhaController.text.trim()),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: const Color(0xFFF8FAFC), // A solid, crisp off-white instead of a hazy gradient  
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // UI Upgrade: Refined Header [cite: 16-18]
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: NexusTheme.primaryBlue.withOpacity(0.2),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        )
                      ],
                    ),
                    child: const Icon(
                      Icons.health_and_safety_rounded, 
                      size: 60, 
                      color: NexusTheme.primaryBlue
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Project Nexus',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      color: NexusTheme.primaryBlue,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Link your health records across hospitals instantly.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16, 
                      color: NexusTheme.textLight,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 48),

                  // UI Upgrade: Error Message Stylizing 
                  if (_errorMessage.isNotEmpty)
                    _buildErrorContainer(),

                  // UI Upgrade: High-Depth Input Card [cite: 23-27, 34-35]
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 40,
                          offset: const Offset(0, 20),
                        )
                      ],
                    ),
                    child: Column(
                      children: [
                        if (!_otpRequired) ...[
                          _buildModernTextField(
                            controller: _abhaController,
                            label: 'ABHA ID',
                            icon: Icons.badge_outlined,
                          ),
                          const SizedBox(height: 16),
                          _buildModernTextField(
                            controller: _nameController,
                            label: 'Full Name',
                            icon: Icons.person_outline,
                          ),
                          const SizedBox(height: 16),
                          _buildModernTextField(
                            controller: _dobController,
                            label: 'Date of Birth (YYYY-MM-DD)',
                            icon: Icons.calendar_month_outlined,
                          ),
                          const SizedBox(height: 32),
                          _buildPrimaryButton(
                            text: 'Discover Records',
                            onPressed: _isLoading ? null : _linkRecord,
                          ),
                        ] else ...[
                          const Text(
                            'Verification Required',
                            style: TextStyle(
                              fontSize: 22, 
                              fontWeight: FontWeight.w800,
                              color: NexusTheme.primaryBlue,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'An OTP has been sent to the mobile registered with ${_abhaController.text}.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: NexusTheme.textLight, height: 1.4),
                          ),
                          const SizedBox(height: 32),
                          _buildModernTextField(
                            controller: _otpController,
                            label: 'Enter 6-Digit OTP',
                            icon: Icons.lock_person_outlined,
                            isOtp: true,
                          ),
                          const SizedBox(height: 32),
                          _buildPrimaryButton(
                            text: 'Verify & Continue',
                            onPressed: _isLoading ? null : _verifyOtp,
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _otpRequired = false;
                                _errorMessage = '';
                              });
                            },
                            child: const Text(
                              'Go Back',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: NexusTheme.textLight,
                              ),
                            ),
                          )
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- UI Helper Components ---

  Widget _buildErrorContainer() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: NexusTheme.errorRed.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NexusTheme.errorRed.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: NexusTheme.errorRed),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage,
              style: const TextStyle(color: NexusTheme.errorRed, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isOtp = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: isOtp ? TextInputType.number : TextInputType.text,
      maxLength: isOtp ? 6 : null,
      decoration: InputDecoration(
        labelText: label,
        counterText: "",
        prefixIcon: Icon(icon, color: NexusTheme.primaryBlue.withOpacity(0.7)),
      ),
    );
  }

  Widget _buildPrimaryButton({required String text, required VoidCallback? onPressed}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
              )
            : Text(text),
      ),
    );
  }
}