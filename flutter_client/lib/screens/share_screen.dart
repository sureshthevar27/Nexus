import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme.dart';

class ShareScreen extends StatefulWidget {
  final Map<String, dynamic> fhirData;
  final String? aiSummary;
  const ShareScreen({super.key, required this.fhirData, this.aiSummary});

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  // Logic variables kept exactly as original [cite: 3, 4]
  bool _isLoading = false;
  String _errorMessage = '';
  Uint8List? _qrImageBytes;
  String? _shareUrl;
  String? _shareId;
  bool _showQr = false;

  bool _shareDemographics = true;
  bool _shareLabs = true;
  bool _shareMedications = true;

  @override
  void initState() {
    super.initState();
  }

  // Logic untouched [cite: 6-16]
  Future<void> _generateQr() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final filteredData = Map<String, dynamic>.from(widget.fhirData);
      if (filteredData['entry'] != null) {
        final entries = List<dynamic>.from(filteredData['entry']);
        filteredData['entry'] = entries.where((entry) {
          final type = entry['resource']?['resourceType'];
          if (type == 'Patient' && !_shareDemographics) return false;
          if (type == 'Observation' && !_shareLabs) return false;
          if ((type == 'MedicationStatement' || type == 'MedicationRequest') && !_shareMedications) return false;
          return true;
        }).toList();
      }

      if (filteredData['contained'] != null) {
        final contained = List<dynamic>.from(filteredData['contained']);
        filteredData['contained'] = contained.where((res) {
          final type = res['resourceType'];
          if (type == 'Patient' && !_shareDemographics) return false;
          if (type == 'Observation' && !_shareLabs) return false;
          if ((type == 'MedicationStatement' || type == 'MedicationRequest') && !_shareMedications) return false;
          return true;
        }).toList();
      }

      if (widget.aiSummary != null && widget.aiSummary!.trim().isNotEmpty) {
        filteredData['ai_summary'] = widget.aiSummary;
      }

      final response = await ApiService.generateQr(filteredData);
      
      final dataUrl = response['qr_data_url'] as String?;
      if (dataUrl != null && dataUrl.startsWith('data:image/png;base64,')) {
        final base64Str = dataUrl.replaceFirst('data:image/png;base64,', '');
        setState(() {
          _qrImageBytes = base64Decode(base64Str);
          _shareUrl = response['share_url'];
          _shareId = response['share_id'];
          _showQr = true;
          _isLoading = false;
        });
      } else {
        throw Exception("Invalid QR data format from server");
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _endSession() async {
    if (_shareId != null) {
      try {
        await ApiService.revokeShare(_shareId!);
      } catch (_) {}
    }
    if (mounted) Navigator.pop(context);
  }

  String _getPatientDisplayName() {
    final names = widget.fhirData['name'] as List<dynamic>? ?? (widget.fhirData['entry'] as List?)?.firstWhere((e) => e['resource']?['resourceType'] == 'Patient', orElse: () => null)?['resource']?['name'] as List<dynamic>?;
    if (names == null || names.isEmpty) return 'Patient';
    final primary = names.first as Map<String, dynamic>;
    return primary['text'] ?? '${primary['given']?[0] ?? ''} ${primary['family'] ?? ''}'.trim();
  }

  @override
  Widget build(BuildContext context) {
    final patientName = _getPatientDisplayName();
    final initials = patientName.split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join('');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: NexusTheme.primaryBlue,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: NexusTheme.accentGold, width: 3)),
        title: const Text('Secure Share Gateway', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: NexusTheme.primaryBlue),
                    const SizedBox(height: 24),
                    Text('Securing health data...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: NexusTheme.primaryBlue.withOpacity(0.7))),
                  ],
                ),
              )
            : _errorMessage.isNotEmpty
                ? _buildErrorUI()
                : _showQr 
                    ? _buildQrUI()
                    : _buildConsentUI(patientName, initials),
      ),
    );
  }

  Widget _buildErrorUI() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 24),
          Text(_errorMessage, style: const TextStyle(fontSize: 14), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => setState(() { _isLoading = true; _errorMessage = ''; _generateQr(); }),
            child: const Text('Retry'),
          )
        ],
      ),
    ),
  );

  Widget _buildConsentUI(String name, String initials) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Patient context header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
          child: Row(children: [
            CircleAvatar(radius: 20, backgroundColor: NexusTheme.accentGold, child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Sharing data for', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600)),
              Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: NexusTheme.primaryBlue)),
            ])),
          ]),
        ),
        const SizedBox(height: 24),
        const Text('Consent Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: NexusTheme.primaryBlue)),
        const SizedBox(height: 8),
        const Text('Select specific clinical records to include in this secure, temporary session link.', style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4)),
        const SizedBox(height: 24),
        
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
          child: Column(children: [
            _buildConsentTile(icon: Icons.person_outline, title: 'Demographics', subtitle: 'Identity, DOB, and Gender', value: _shareDemographics, onChanged: (v) => setState(() => _shareDemographics = v)),
            const Divider(height: 1, indent: 60),
            _buildConsentTile(icon: Icons.monitor_heart_outlined, title: 'Vitals & Labs', subtitle: 'Historical health metrics', value: _shareLabs, onChanged: (v) => setState(() => _shareLabs = v)),
            const Divider(height: 1, indent: 60),
            _buildConsentTile(icon: Icons.medication_outlined, title: 'Medications', subtitle: 'Active prescriptions', value: _shareMedications, onChanged: (v) => setState(() => _shareMedications = v)),
          ]),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: NexusTheme.primaryBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: _generateQr,
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.qr_code, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('Generate Secure Gateway', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
      ],
    ),
  );

  Widget _buildQrUI() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        const Icon(Icons.shield_outlined, size: 60, color: NexusTheme.accentTeal),
        const SizedBox(height: 16),
        const Text('Session Encrypted', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: NexusTheme.primaryBlue)),
        const SizedBox(height: 8),
        const Text('Present this QR to the hospital official. Access is revoked instantly when you end the session.', style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4), textAlign: TextAlign.center),
        const SizedBox(height: 40),
        
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [BoxShadow(color: NexusTheme.primaryBlue.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))],
          ),
          child: Column(children: [
            if (_qrImageBytes != null)
              Image.memory(_qrImageBytes!, width: 200, height: 200)
            else
              const SizedBox(width: 200, height: 200, child: Center(child: Text('QR Error'))),
            const SizedBox(height: 16),
            const Text('TEMPORARY ACCESS TOKEN', style: TextStyle(fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: Colors.grey)),
            if (_shareId != null) ...[
              const SizedBox(height: 4),
              Text(_shareId!.substring(0, 8).toUpperCase(), style: const TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w700, color: NexusTheme.primaryBlue)),
            ]
          ]),
        ),
        const SizedBox(height: 48),
        SizedBox(
          width: 200,
          height: 50,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: _endSession,
            icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 20),
            label: const Text('End Session', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
    ),
  );

  Widget _buildConsentTile({required IconData icon, required String title, required String subtitle, required bool value, required Function(bool) onChanged}) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      value: value,
      activeColor: NexusTheme.accentTeal,
      onChanged: onChanged,
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: NexusTheme.primaryBlue.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: NexusTheme.primaryBlue, size: 22),
      ),
    );
  }
}