import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme.dart';
import 'share_screen.dart';
import 'intelligence_screen.dart';
import 'discovery_screen.dart';

class DashboardScreen extends StatefulWidget {
  final String abhaId;

  const DashboardScreen({super.key, required this.abhaId});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedTab = 0;
  bool _isLoading = true;
  String _errorMessage = '';
  Map<String, dynamic>? _fhirData;
  String? _aiSummary;
  bool _isSummaryLoading = false;

  // Global Consent State
  bool _consentRiskSignals = true;
  bool _consentTreatmentPatterns = true;
  bool _consentClinicalContext = true;
  bool _consentGovernance = true;

  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String _searchSummary = '';
  bool _searchFailed = false;
  List<Map<String, dynamic>> _searchMatches = [];

  @override
  void initState() {
    super.initState();
    _fetchPatientData(isRefresh: false);
  }

  Future<void> _fetchPatientData({bool isRefresh = true}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final data = await ApiService.getPatientFHIRFast(widget.abhaId);
      setState(() {
        _fhirData = data;
        _aiSummary = null;
      });
      _fetchAiSummary(forceRefresh: isRefresh);
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

  Future<void> _fetchAiSummary({bool forceRefresh = false}) async {
    setState(() {
      _isSummaryLoading = true;
    });

    try {
      final summary = await ApiService.getPatientSummary(widget.abhaId, 
        forceRefresh: forceRefresh,
        consent: {
          'risk_signals': _consentRiskSignals,
          'treatment_patterns': _consentTreatmentPatterns,
          'clinical_context': _consentClinicalContext,
          'consent_status': _consentGovernance,
        }
      );
      setState(() {
        _aiSummary = summary;
      });
    } catch (_) {
      setState(() {
        _aiSummary = null;
      });
    } finally {
      setState(() {
        _isSummaryLoading = false;
      });
    }
  }

  Future<void> _performSearch() async {
  final query = _searchController.text.trim();
  if (query.isEmpty) return;
  setState(() {
    _isSearching = true;
    _searchSummary = '';
    _searchMatches = [];
  });
  try {
    final result = await ApiService.searchTimeline(widget.abhaId, query);
    setState(() {
      // Logic Restored: Ensure summary is captured [cite: 373]
      final summary = result['summary']?.toString().trim();
      _searchSummary = (summary == null || summary.isEmpty) ? 'No results found.' : summary;
      
      // Logic Restored: Ensure matches are cast correctly for the UI [cite: 373, 374]
      final matches = (result['matches'] as List?) ?? [];
      _searchMatches = matches.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    });
  } catch (e) {
    setState(() { _searchFailed = true; _searchSummary = 'Search failed: $e'; });
  } finally {
    setState(() { _isSearching = false; });
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

  // Logic Restored: Helper to clean strings [cite: 398]
  String? takeText(dynamic value) => value is String && value.trim().isNotEmpty ? value.trim() : null;

  // Logic Restored: Helper to build summary rows safely [cite: 399]
  void addRow(String label, String? value) {
    if (value == null || value.trim().isEmpty) return;
    rows.add(_buildDetailRow(label, value));
  }

  // FHIR Mapping 
  if (type == 'Observation') {
    addRow('Test', takeText(resource['code']?['text']));
    final valueObj = resource['valueQuantity'];
    if (valueObj != null) {
      addRow('Value', '${valueObj['value']} ${valueObj['unit'] ?? ''}'.trim());
    }
  } else if (type == 'Condition') {
    addRow('Diagnosis', takeText(resource['code']?['text']));
    addRow('Status', takeText(resource['clinicalStatus']?['coding']?[0]?['code']));
  } else if (type == 'MedicationRequest') {
    addRow('Medication', takeText(resource['medicationCodeableConcept']?['text']));
  }

  if (rows.isEmpty) {
    rows.add(const Text('No summary details available.', style: TextStyle(color: Colors.grey)));
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: rows,
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

  // ── NEW UI HELPERS (design-reference) ──────────────────────────────

  Widget _buildLoadingState() => const Center(child: CircularProgressIndicator());

  Widget _buildErrorState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 48, color: Colors.red),
        const SizedBox(height: 16),
        Text(_errorMessage, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: () => _fetchPatientData(isRefresh: true), child: const Text('Retry')),
      ],
    ),
  );

  Widget _buildPatientHeader(String name, String initials, int? age, String gender, List<String> conditions) {
    final subtitle = [
      if (age != null) '${age}M',
      widget.abhaId,
    ].join(' · ');
    return Container(
      color: NexusTheme.primaryBlue,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: NexusTheme.accentGold,
            child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12)),
          ])),
        ]),
        if (conditions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, children: conditions.map((c) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
            child: Text(c, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          )).toList()),
        ],
      ]),
    );
  }

  Widget _buildDrugAlert(String msg) => Container(
    color: const Color(0xFFFFF3CD),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(children: [
      const Icon(Icons.warning_amber_rounded, color: Color(0xFF856404), size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(msg, style: const TextStyle(color: Color(0xFF856404), fontSize: 12, fontWeight: FontWeight.w600))),
    ]),
  );


  Widget _buildHomeTab(List<dynamic> vitals, List<dynamic> all) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      // AI Summary card
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: const [
            Icon(Icons.auto_awesome, color: NexusTheme.accentTeal, size: 16),
            SizedBox(width: 6),
            Text('AI Clinical Summary', style: TextStyle(fontWeight: FontWeight.bold, color: NexusTheme.accentTeal, fontSize: 13)),
          ]),
          const SizedBox(height: 8),
          if (_isSummaryLoading)
            const LinearProgressIndicator()
          else
            Text(_aiSummary ?? 'Summary will appear once available.', style: const TextStyle(fontSize: 13, height: 1.5)),
        ]),
      ),
      // Quick search
      TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search records (e.g. "glucose")',
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: _isSearching
              ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(icon: const Icon(Icons.send, size: 18), onPressed: _performSearch),
          filled: true, fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        ),
        onSubmitted: (_) => _performSearch(),
      ),
      if (_searchSummary.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF9C4), // Material Yellow 100
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFBC02D).withOpacity(0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.lightbulb_outline, color: Color(0xFFF57F17), size: 16),
                  SizedBox(width: 4),
                  Text('Search Insight', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFF57F17), fontSize: 12)),
                ],
              ),
              const SizedBox(height: 4),
              Text(_searchSummary, style: const TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF5D4037))),
            ],
          ),
        ),
      ],
      if (_searchMatches.isNotEmpty) ...[
        const SizedBox(height: 12),
        const Text('Search Results', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 6),
        ..._searchMatches.map(_buildSearchResultCard),
      ],
      // AI Risk analysis shortcut
      const SizedBox(height: 16),
      GestureDetector(
        onTap: () {
          Navigator.push(
            context, 
            MaterialPageRoute(
              builder: (_) => IntelligenceScreen(
                abhaId: widget.abhaId,
                consentRiskSignals: _consentRiskSignals,
                consentTreatmentPatterns: _consentTreatmentPatterns,
                consentClinicalContext: _consentClinicalContext,
                consentGovernance: _consentGovernance,
                onConsentChanged: (risk, pattern, ctx, gov) {
                  setState(() {
                    _consentRiskSignals = risk;
                    _consentTreatmentPatterns = pattern;
                    _consentClinicalContext = ctx;
                    _consentGovernance = gov;
                  });
                  // Force refresh dashboard summary to apply new consent
                  _fetchAiSummary(forceRefresh: true);
                },
              )
            )
          );
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
          child: Row(children: const [
            Icon(Icons.psychology, color: NexusTheme.primaryBlue),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('AI Risk Analysis', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text('Risk signals, patterns, context, governance', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ])),
            Icon(Icons.chevron_right, color: Colors.grey),
          ]),
        ),
      ),
    ],
  );

  Widget _buildVitalsTab(List<dynamic> vitals) {
    if (vitals.isEmpty) return const Center(child: Text('No vitals data available.', style: TextStyle(color: Colors.grey)));
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.4),
      itemCount: vitals.length,
      itemBuilder: (_, i) {
        final v = vitals[i] as Map<String, dynamic>;
        final label = v['code']?['text'] ?? v['code']?['coding']?[0]?['display'] ?? 'Observation';
        final vq = v['valueQuantity'];
        final value = vq != null ? '${vq['value']}' : (v['valueString'] ?? '--');
        final unit = vq?['unit'] ?? '';
        final interp = v['interpretation']?[0]?['coding']?[0]?['display'] ?? v['interpretation']?[0]?['text'] ?? '';
        Color statusColor = Colors.grey;
        if (interp.toLowerCase().contains('normal')) statusColor = Colors.green;
        else if (interp.toLowerCase().contains('high') || interp.toLowerCase().contains('border')) statusColor = Colors.orange;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: NexusTheme.primaryBlue)),
              const SizedBox(width: 4),
              Text(unit, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
            if (interp.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                child: Text(interp, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w600)),
              ),
          ]),
        );
      },
    );
  }

  Widget _buildRecordsTab(List<dynamic> all) {
    if (all.isEmpty) return const Center(child: Text('No clinical records found.', style: TextStyle(color: Colors.grey)));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: all.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _buildTimelineCard(all[i] as Map<String, dynamic>),
    );
  }

  Widget _buildTimelineCard(Map<String, dynamic> resource) {
    final type = resource['resourceType'] ?? '';
    String title = 'Record', subtitle = '', date = '', trail = '';
    IconData icon = Icons.article_outlined;
    Color color = NexusTheme.primaryBlue;

    if (type == 'Observation') {
      title = resource['code']?['text'] ?? resource['code']?['coding']?[0]?['display'] ?? 'Observation';
      final vq = resource['valueQuantity'];
      trail = vq != null ? '${vq['value']} ${vq['unit'] ?? ''}' : (resource['valueString'] ?? '');
      subtitle = 'Vital / Lab';
      date = resource['effectiveDateTime']?.toString().substring(0, 10) ?? '';
      icon = Icons.monitor_heart_outlined; color = NexusTheme.accentTeal;
    } else if (type == 'Condition') {
      title = resource['code']?['text'] ?? 'Diagnosis';
      subtitle = resource['clinicalStatus']?['coding']?[0]?['code'] ?? 'Condition';
      date = resource['onsetDateTime']?.toString().substring(0, 10) ?? resource['recordedDate']?.toString().substring(0, 10) ?? '';
      icon = Icons.healing_outlined; color = Colors.redAccent;
    } else if (type == 'MedicationRequest' || type == 'MedicationStatement') {
      title = resource['medicationCodeableConcept']?['text'] ?? 'Medication';
      subtitle = resource['dosage']?[0]?['text'] ?? 'Prescription';
      date = resource['authoredOn']?.toString().substring(0, 10) ?? '';
      icon = Icons.medication_outlined; color = Colors.purple;
    } else if (type == 'Encounter') {
      title = resource['type']?[0]?['text'] ?? 'Clinical Visit';
      subtitle = resource['serviceProvider']?['display'] ?? resource['status'] ?? 'Visit';
      date = resource['period']?['start']?.toString().substring(0, 10) ?? '';
      icon = Icons.local_hospital_outlined; color = Colors.orange;
    }

    return GestureDetector(
      onTap: () => _showResourceDetails(resource),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (date.isNotEmpty) Text(date, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            if (trail.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(trail, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
            ],
          ]),
        ]),
      ),
    );
  }

  Widget _buildProfileTab(Map<String, dynamic>? p) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _profileRow('Full Name', _getPatientDisplayName(p)),
      _profileRow('ABHA ID', widget.abhaId),
      _profileRow('Date of Birth', p?['birthDate'] ?? '--'),
      _profileRow('Gender', p?['gender'] ?? '--'),
    ],
  );

  Widget _profileRow(String label, String value) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
    child: Row(children: [
      SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600))),
      Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
    ]),
  );

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
        trailing: trailingText.isNotEmpty ? ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: Text(
            trailingText,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: NexusTheme.primaryBlue),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
          ),
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
    final patientName = _getPatientDisplayName(patientRes);
    final dob = patientRes?['birthDate']?.toString() ?? '';

    int? age;
    if (dob.isNotEmpty) {
      try { age = DateTime.now().year - DateTime.parse(dob).year; } catch (_) {}
    }
    final gender = patientRes?['gender']?.toString() ?? '';
    final conditions = clinicalItems
        .where((item) => item is Map && item['resourceType'] == 'Condition')
        .map((item) => (item as Map)['code']?['text']?.toString() ?? '')
        .where((c) => c.isNotEmpty).take(3).toList();
    final vitals = clinicalItems
        .where((item) => item is Map && item['resourceType'] == 'Observation')
        .map((item) => item as Map<String, dynamic>).toList();
    final hasMeds = clinicalItems.any((item) => item is Map &&
        (item['resourceType'] == 'MedicationRequest' || item['resourceType'] == 'MedicationStatement'));
    final initials = patientName.split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join('');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: NexusTheme.primaryBlue,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: NexusTheme.accentGold, width: 3)),
        leadingWidth: 40,
        leading: const Padding(padding: EdgeInsets.only(left: 12), child: Icon(Icons.health_and_safety, color: Colors.white, size: 22)),
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Project Nexus', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          Text('National Health Gateway', style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 10)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white, size: 20), onPressed: () => _fetchPatientData(isRefresh: true)),
          IconButton(icon: const Icon(Icons.logout, color: Colors.white, size: 20), onPressed: () {
            Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const DiscoveryScreen()), (_) => false);
          }),
        ],
      ),
      body: _isLoading
          ? _buildLoadingState()
          : _errorMessage.isNotEmpty
              ? _buildErrorState()
              : Column(children: [
                  _buildPatientHeader(patientName, initials, age, gender, conditions),
                  if (hasMeds && conditions.isNotEmpty)
                    _buildDrugAlert('Drug interaction detected — Review medication combinations'),
                  Expanded(
                    child: IndexedStack(index: _selectedTab, children: [
                      _buildHomeTab(vitals, clinicalItems),
                      _buildVitalsTab(vitals),
                      _buildRecordsTab(clinicalItems),
                      _buildProfileTab(patientRes),
                    ]),
                  ),
                ]),
      floatingActionButton: (_selectedTab == 0 || _selectedTab == 2) ? FloatingActionButton.extended(
        heroTag: 'share',
        backgroundColor: NexusTheme.primaryBlue,
        icon: const Icon(Icons.qr_code, color: Colors.white),
        label: const Text('Share', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        onPressed: () {
          if (_fhirData != null) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => ShareScreen(fhirData: _fhirData!, aiSummary: _aiSummary)));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No data to share yet!')));
          }
        },
      ) : null,
      bottomNavigationBar: _isLoading || _errorMessage.isNotEmpty ? null : BottomNavigationBar(
        currentIndex: _selectedTab,
        onTap: (i) => setState(() => _selectedTab = i),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: NexusTheme.primaryBlue,
        unselectedItemColor: Colors.grey.shade400,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined, size: 22), activeIcon: Icon(Icons.home, size: 22), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.monitor_heart_outlined, size: 22), activeIcon: Icon(Icons.monitor_heart, size: 22), label: 'Vitals'),
          BottomNavigationBarItem(icon: Icon(Icons.folder_outlined, size: 22), activeIcon: Icon(Icons.folder, size: 22), label: 'Records'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline, size: 22), activeIcon: Icon(Icons.person, size: 22), label: 'Profile'),
        ],
      ),
    );
  }
}
