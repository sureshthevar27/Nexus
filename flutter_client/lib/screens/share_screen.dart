import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme.dart';

class ShareScreen extends StatefulWidget {
  final Map<String, dynamic> fhirData;

  const ShareScreen({super.key, required this.fhirData});

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  bool _isLoading = false;
  String _errorMessage = '';
  Uint8List? _qrImageBytes;
  String? _shareUrl;
  bool _showQr = false;

  bool _shareDemographics = true;
  bool _shareLabs = true;
  bool _shareMedications = true;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _generateQr() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final filteredData = Map<String, dynamic>.from(widget.fhirData);
      
      // Filter entries based on consent
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

      // Filter contained resources
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

      final response = await ApiService.generateQr(filteredData);
      
      final dataUrl = response['qr_data_url'] as String?;
      if (dataUrl != null && dataUrl.startsWith('data:image/png;base64,')) {
        final base64Str = dataUrl.replaceFirst('data:image/png;base64,', '');
        setState(() {
          _qrImageBytes = base64Decode(base64Str);
          _shareUrl = response['share_url'];
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Share Health Passport'),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Securing health data in vault...'),
                  ],
                ),
              )
            : _errorMessage.isNotEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, size: 64, color: Colors.red),
                          const SizedBox(height: 16),
                          Text(_errorMessage, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _isLoading = true;
                                _errorMessage = '';
                              });
                              _generateQr();
                            },
                            child: const Text('Retry Generating QR'),
                          )
                        ],
                      ),
                    ),
                  )
                : _showQr 
                    ? Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.security, size: 60, color: NexusTheme.accentTeal),
                              const SizedBox(height: 16),
                              const Text(
                                'Your Data is Ready to Share',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: NexusTheme.primaryBlue,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Show this QR code to the receiving hospital. It contains a secure, one-time link to your filtered FHIR records.',
                                style: TextStyle(fontSize: 16, color: Colors.grey),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 40),
                              
                              // QR Code Container
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 20,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    if (_qrImageBytes != null)
                                      Image.memory(
                                        _qrImageBytes!,
                                        width: 200,
                                        height: 200,
                                        fit: BoxFit.contain,
                                      )
                                    else
                                      const SizedBox(
                                        width: 200,
                                        height: 200,
                                        child: Center(child: Text('QR Code Error')),
                                      ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Scan with Nexus Receiver',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: NexusTheme.textDark,
                                      ),
                                    ),
                                    if (_shareUrl != null) ...
                                      [
                                        const SizedBox(height: 8),
                                        Text(
                                          _shareUrl!,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ],
                                  ],
                                ),
                              ),
                              
                              const SizedBox(height: 40),
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                },
                                icon: const Icon(Icons.check),
                                label: const Text('Done Sharing'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: NexusTheme.primaryBlue,
                                  side: const BorderSide(color: NexusTheme.primaryBlue),
                                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                                ),
                              )
                            ],
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Granular Data Consent',
                              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: NexusTheme.primaryBlue),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Select exactly what clinical data you want to securely package into this QR code session.',
                              style: TextStyle(fontSize: 16, color: Colors.grey),
                            ),
                            const SizedBox(height: 32),
                            Card(
                              child: Column(
                                children: [
                                  SwitchListTile(
                                    title: const Text('Basic Demographics'),
                                    subtitle: const Text('Name, DOB, Contact Info'),
                                    value: _shareDemographics,
                                    activeColor: NexusTheme.accentTeal,
                                    onChanged: (val) => setState(() => _shareDemographics = val),
                                    secondary: const Icon(Icons.person),
                                  ),
                                  const Divider(height: 1),
                                  SwitchListTile(
                                    title: const Text('Labs & Vitals'),
                                    subtitle: const Text('Glucose, BP, and test results'),
                                    value: _shareLabs,
                                    activeColor: NexusTheme.accentTeal,
                                    onChanged: (val) => setState(() => _shareLabs = val),
                                    secondary: const Icon(Icons.monitor_heart),
                                  ),
                                  const Divider(height: 1),
                                  SwitchListTile(
                                    title: const Text('Prescriptions'),
                                    subtitle: const Text('Current and past medications'),
                                    value: _shareMedications,
                                    activeColor: NexusTheme.accentTeal,
                                    onChanged: (val) => setState(() => _shareMedications = val),
                                    secondary: const Icon(Icons.medication),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 40),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _generateQr,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: NexusTheme.primaryBlue,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Generate Secure QR', style: TextStyle(fontSize: 18)),
                              ),
                            ),
                          ],
                        ),
                      ),
      ),
    );
  }
}
