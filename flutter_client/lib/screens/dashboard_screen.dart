import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme.dart';
import 'share_screen.dart';

class DashboardScreen extends StatefulWidget {
  final String abhaId;

  const DashboardScreen({super.key, required this.abhaId});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;
  String _errorMessage = '';
  Map<String, dynamic>? _fhirData;

  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String _searchSummary = '';
  bool _searchFailed = false;
  List<Map<String, dynamic>> _searchMatches = [];

  @override
  void initState() {
    super.initState();
    _fetchPatientData();
  }

  Future<void> _fetchPatientData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final data = await ApiService.getPatientFHIR(widget.abhaId);
      setState(() {
        _fhirData = data;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchSummary = '';
      _searchFailed = false;
      _searchMatches = [];
    });

    try {
      final result = await ApiService.searchTimeline(widget.abhaId, query);
      setState(() {
        final summary = result['summary']?.toString().trim();
        _searchSummary = (summary == null || summary.isEmpty)
            ? 'No results found.'
            : summary;
        final matches = (result['matches'] as List?) ?? [];
        _searchMatches = matches
            .whereType<Map>()
            .map((match) => Map<String, dynamic>.from(match))
            .toList();
      });
    } catch (e) {
      setState(() {
        _searchFailed = true;
        _searchSummary = 'Search failed: ${e.toString().replaceAll('Exception: ', '')}';
      });
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  Map<String, dynamic>? _getPatientResource() {
    if (_fhirData == null) return null;
    
    if (_fhirData!['resourceType'] == 'Patient') return _fhirData;
    
    if (_fhirData!['entry'] != null) {
      for (var entry in _fhirData!['entry']) {
        if (entry['resource'] != null && entry['resource']['resourceType'] == 'Patient') {
          return entry['resource'];
        }
      }
    }
    
    if (_fhirData!['contained'] != null) {
      for (var res in _fhirData!['contained']) {
        if (res['resourceType'] == 'Patient') return res;
      }
    }
    return null;
  }

  String _getPatientDisplayName(Map<String, dynamic>? patientRes) {
    if (patientRes == null) return 'Patient Name';
    final names = patientRes['name'] as List<dynamic>?;
    if (names == null || names.isEmpty) return 'Patient Name';

    final primary = names.first as Map<String, dynamic>;
    final text = primary['text'] as String?;
    if (text != null && text.trim().isNotEmpty) return text.trim();

    final family = primary['family'] as String?;
    final given = (primary['given'] as List<dynamic>?)
        ?.whereType<String>()
        .toList();
    final givenText = given != null ? given.join(' ') : '';

    final full = [givenText, family].where((part) => part != null && part!.trim().isNotEmpty).join(' ').trim();
    return full.isNotEmpty ? full : 'Patient Name';
  }

  List<dynamic> _extractClinicalData() {
    List<dynamic> clinicalItems = [];
    
    // Server data
    if (_fhirData != null) {
      if (_fhirData!['contained'] != null) {
        clinicalItems.addAll((_fhirData!['contained'] as List)
            .where((res) => res['resourceType'] != 'Patient'));
      }
      if (_fhirData!['entry'] != null) {
         for (var entry in _fhirData!['entry']) {
           if (entry['resource'] != null && entry['resource']['resourceType'] != 'Patient') {
             clinicalItems.add(entry['resource']);
           }
         }
      }
    }
    
    return clinicalItems;
  }

  void _showResourceDetails(Map<String, dynamic> resource) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            controller: scrollController,
            children: [
              Row(
                children: [
                  const Icon(Icons.description, color: NexusTheme.primaryBlue),
                  const SizedBox(width: 8),
                  Text(
                    resource['resourceType']?.toString() ?? 'Record Details',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Details', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _buildResourceDetails(resource),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResourceSummary(Map<String, dynamic> resource) {
    final type = resource['resourceType']?.toString() ?? 'Record';
    final rows = <Widget>[];

    String? takeText(dynamic value) => value is String && value.trim().isNotEmpty ? value.trim() : null;

    void addRow(String label, String? value) {
      if (value == null || value.trim().isEmpty) return;
      rows.add(_buildDetailRow(label, value));
    }

    if (type == 'Observation') {
      addRow('Test', takeText(resource['code']?['text']));
      addRow('Status', takeText(resource['status']));
      addRow('Effective', takeText(resource['effectiveDateTime']));
      final valueObj = resource['valueQuantity'];
      if (valueObj != null) {
        final valueText = '${valueObj['value'] ?? ''} ${valueObj['unit'] ?? ''}'.trim();
        addRow('Value', valueText);
      } else {
        addRow('Value', takeText(resource['valueString']));
      }
    } else if (type == 'MedicationStatement' || type == 'MedicationRequest') {
      addRow('Medication', takeText(resource['medicationCodeableConcept']?['text']));
      addRow('Status', takeText(resource['status']));
      addRow('Dosage', takeText(resource['dosage']?[0]?['text']));
      addRow('Authored On', takeText(resource['authoredOn']));
    } else if (type == 'Encounter') {
      addRow('Visit Type', takeText(resource['type']?[0]?['text']));
      addRow('Status', takeText(resource['status']));
      addRow('Start', takeText(resource['period']?['start']));
      addRow('End', takeText(resource['period']?['end']));
      addRow('Reason', takeText(resource['reasonCode']?[0]?['text']));
    } else if (type == 'Condition') {
      addRow('Condition', takeText(resource['code']?['text']));
      addRow('Status', takeText(resource['clinicalStatus']?['coding']?[0]?['code']));
      addRow('Verification', takeText(resource['verificationStatus']?['coding']?[0]?['code']));
      addRow('Onset', takeText(resource['onsetDateTime']));
    }

    if (rows.isEmpty) {
      rows.add(const Text('No summary details available.'));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        ),
      ),
    );
  }

  Widget _buildResourceDetails(Map<String, dynamic> resource) {
    final type = resource['resourceType']?.toString() ?? 'Record';
    final rows = <Widget>[];

    void addRow(String label, String? value) {
      if (value == null || value.trim().isEmpty) return;
      rows.add(_buildDetailRow(label, value));
    }

    if (type == 'Observation') {
      addRow('Test', _codeableText(resource['code']));
      addRow('Status', _stringValue(resource['status']));
      addRow('Effective', _stringValue(resource['effectiveDateTime']));
      addRow('Category', _codeableText(resource['category']?[0]));
      addRow('Value', _valueQuantityText(resource['valueQuantity']) ?? _stringValue(resource['valueString']));
      addRow('Interpretation', _codeableText(resource['interpretation']?[0]));
      addRow('Body Site', _codeableText(resource['bodySite']));
    } else if (type == 'MedicationStatement' || type == 'MedicationRequest') {
      addRow('Medication', _codeableText(resource['medicationCodeableConcept']));
      addRow('Status', _stringValue(resource['status']));
      addRow('Dosage', _stringValue(resource['dosage']?[0]?['text']));
      addRow('Authored On', _stringValue(resource['authoredOn']));
      addRow('Route', _codeableText(resource['dosage']?[0]?['route']));
      addRow('Frequency', _dosageTimingText(resource['dosage']?[0]?['timing']));
    } else if (type == 'Encounter') {
      addRow('Visit Type', _codeableText(resource['type']?[0]));
      addRow('Status', _stringValue(resource['status']));
      addRow('Class', _codeableText(resource['class']));
      addRow('Period', _periodRange(resource['period']));
      addRow('Reason', _codeableText(resource['reasonCode']?[0]));
      addRow('Service Provider', _stringValue(resource['serviceProvider']?['display']));
    } else if (type == 'Condition') {
      addRow('Condition', _codeableText(resource['code']));
      addRow('Clinical Status', _codeableText(resource['clinicalStatus']));
      addRow('Verification', _codeableText(resource['verificationStatus']));
      addRow('Onset', _stringValue(resource['onsetDateTime']));
      addRow('Recorded', _stringValue(resource['recordedDate']));
      addRow('Severity', _codeableText(resource['severity']));
    } else {
      final entries = resource.entries
          .where((entry) => entry.value is! Map && entry.value is! List)
          .toList();
      for (final entry in entries) {
        addRow(_titleCase(entry.key.toString()), _stringValue(entry.value));
      }
    }

    if (rows.isEmpty) {
      rows.add(const Text('No additional details available.'));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        ),
      ),
    );
  }

  String? _stringValue(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  String? _codeableText(dynamic codeable) {
    if (codeable == null) return null;
    if (codeable is String) return _stringValue(codeable);
    final text = codeable['text']?.toString().trim();
    if (text != null && text.isNotEmpty) return text;
    final coding = codeable['coding'] as List?;
    if (coding != null && coding.isNotEmpty) {
      return _stringValue(coding.first['display']) ?? _stringValue(coding.first['code']);
    }
    return null;
  }

  String? _valueQuantityText(dynamic valueQuantity) {
    if (valueQuantity == null) return null;
    final value = valueQuantity['value']?.toString().trim();
    final unit = valueQuantity['unit']?.toString().trim();
    if (value == null || value.isEmpty) return null;
    return unit == null || unit.isEmpty ? value : '$value $unit';
  }

  String? _periodRange(dynamic period) {
    if (period == null) return null;
    final start = _stringValue(period['start']);
    final end = _stringValue(period['end']);
    if (start == null && end == null) return null;
    if (start != null && end != null) return '$start - $end';
    return start ?? end;
  }

  String? _dosageTimingText(dynamic timing) {
    if (timing == null) return null;
    final repeat = timing['repeat'];
    if (repeat == null) return null;
    final frequency = repeat['frequency'];
    final period = repeat['period'];
    final unit = repeat['periodUnit'];
    if (frequency == null || period == null || unit == null) return null;
    return '$frequency times every $period $unit';
  }

  String _titleCase(String input) {
    if (input.isEmpty) return input;
    return input
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClinicalCard(Map<String, dynamic> resource) {
    final type = resource['resourceType'];
    String title = 'Record';
    String subtitle = type;
    String trailingText = '';
    IconData icon = Icons.medical_information;
    Color iconColor = NexusTheme.primaryBlue;

    if (type == 'Observation') {
      title = resource['code']?['text'] ?? resource['code']?['coding']?[0]?['display'] ?? 'Observation';
      final valueObj = resource['valueQuantity'];
      if (valueObj != null) {
        trailingText = '${valueObj['value']} ${valueObj['unit'] ?? ''}';
      } else if (resource['valueString'] != null) {
        trailingText = resource['valueString'];
      }
      icon = Icons.monitor_heart;
      iconColor = NexusTheme.accentTeal;
      subtitle = 'Vital / Lab';
    } else if (type == 'MedicationStatement' || type == 'MedicationRequest') {
      title = resource['medicationCodeableConcept']?['text'] ?? 'Medication';
      final dosage = resource['dosage']?[0];
      if (dosage != null) {
        subtitle = dosage['text'] ?? 'Prescription';
      } else {
        subtitle = 'Prescription';
      }
      icon = Icons.medication;
      iconColor = Colors.purple;
    } else if (type == 'Encounter') {
      title = resource['type']?[0]?['text'] ?? 'Clinical Visit';
      subtitle = resource['period']?['start'] ?? 'Visit';
      icon = Icons.local_hospital;
      iconColor = Colors.orange;
    } else if (type == 'Condition') {
      title = resource['code']?['text'] ?? 'Diagnosis';
      subtitle = resource['clinicalStatus']?['coding']?[0]?['code'] ?? 'Condition';
      icon = Icons.healing;
      iconColor = Colors.redAccent;
    }

    return Card(
      child: ListTile(
        onTap: () => _showResourceDetails(resource),
        leading: CircleAvatar(
          backgroundColor: iconColor.withOpacity(0.2),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: trailingText.isNotEmpty ? Text(
          trailingText,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: NexusTheme.primaryBlue),
        ) : null,
      ),
    );
  }

  Widget _buildSearchResultCard(Map<String, dynamic> match) {
    final resource = match['resource'] as Map<String, dynamic>?;
    final type = match['resource_type']?.toString() ?? resource?['resourceType']?.toString();
    final title = match['title']?.toString()
        ?? resource?['code']?['text']
        ?? resource?['medicationCodeableConcept']?['text']
        ?? resource?['type']?[0]?['text']
        ?? type
        ?? 'Record';
    final summary = match['summary']?.toString() ?? '';

    return Card(
      child: ListTile(
        onTap: resource == null ? null : () => _showResourceDetails(resource),
        leading: CircleAvatar(
          backgroundColor: NexusTheme.accentTeal.withOpacity(0.2),
          child: const Icon(Icons.search, color: NexusTheme.accentTeal),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (type != null) Text(type, style: const TextStyle(color: Colors.grey)),
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(summary),
            ],
          ],
        ),
        isThreeLine: summary.isNotEmpty,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clinicalItems = _extractClinicalData();
    final patientRes = _getPatientResource();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Passport'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchPatientData,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_errorMessage, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _fetchPatientData,
                        child: const Text('Retry'),
                      )
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchPatientData,
                  child: ListView(
                    padding: const EdgeInsets.all(16.0),
                    children: [
                      Card(
                        color: NexusTheme.primaryBlue,
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Row(
                            children: [
                              const CircleAvatar(
                                radius: 30,
                                backgroundColor: Colors.white,
                                child: Icon(Icons.person, size: 40, color: NexusTheme.primaryBlue),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _getPatientDisplayName(patientRes),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'ABHA: ${widget.abhaId}',
                                      style: TextStyle(color: Colors.white.withOpacity(0.8)),
                                    ),
                                    Text(
                                      'DOB: ${patientRes?['birthDate'] ?? 'Unknown'}',
                                      style: TextStyle(color: Colors.white.withOpacity(0.8)),
                                    ),
                                  ],
                                ),
                              )
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_fhirData?['ai_insights']?['clinical_summary'] != null)
                        Card(
                          color: NexusTheme.accentTeal.withOpacity(0.1),
                          shape: RoundedRectangleBorder(
                            side: const BorderSide(color: NexusTheme.accentTeal, width: 1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: const [
                                    Icon(Icons.auto_awesome, color: NexusTheme.accentTeal),
                                    SizedBox(width: 8),
                                    Text('AI Clinical Summary', style: TextStyle(fontWeight: FontWeight.bold, color: NexusTheme.accentTeal)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(_fhirData!['ai_insights']['clinical_summary']),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search timeline (e.g. "glucose")',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _isSearching 
                              ? const Padding(
                                  padding: EdgeInsets.all(12.0),
                                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                )
                              : IconButton(
                                  icon: const Icon(Icons.arrow_forward),
                                  onPressed: _performSearch,
                                ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onSubmitted: (_) => _performSearch(),
                      ),
                      if (_searchMatches.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Search Results',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              ..._searchMatches.map(_buildSearchResultCard).toList(),
                            ],
                          ),
                        ),
                      if (_searchMatches.isNotEmpty && _searchSummary.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 16.0),
                          child: Card(
                            color: _searchFailed ? Colors.red.shade50 : Colors.amber.shade50,
                            shape: RoundedRectangleBorder(
                              side: BorderSide(
                                color: _searchFailed ? Colors.red.shade200 : Colors.amber.shade300,
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        _searchFailed ? Icons.error_outline : Icons.lightbulb_outline,
                                        color: _searchFailed ? Colors.red.shade600 : Colors.amber.shade800,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _searchFailed ? 'Search Error' : 'Search Summary',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: _searchFailed ? Colors.red.shade600 : Colors.amber.shade800,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(_searchSummary),
                                ],
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Text(
                          'Medical History',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (clinicalItems.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(
                            child: Text(
                              'No clinical data found in the network.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        ...clinicalItems.map((item) => _buildClinicalCard(item as Map<String, dynamic>)).toList(),
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'share',
        backgroundColor: NexusTheme.primaryBlue,
        onPressed: () {
          // Ensure we have data to share
          if (_fhirData != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ShareScreen(fhirData: _fhirData!),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No data to share yet!')),
            );
          }
        },
        child: const Icon(Icons.qr_code, color: Colors.white),
      ),
    );
  }
}
