import 'package:flutter/material.dart';
import '../models/agentic_synthesis.dart';
import '../services/api_service.dart';
import '../theme.dart';

class IntelligenceScreen extends StatefulWidget {
  final String abhaId;
  final bool consentRiskSignals;
  final bool consentTreatmentPatterns;
  final bool consentClinicalContext;
  final bool consentGovernance;
  final Function(bool, bool, bool, bool) onConsentChanged;

  const IntelligenceScreen({
    super.key, 
    required this.abhaId,
    required this.consentRiskSignals,
    required this.consentTreatmentPatterns,
    required this.consentClinicalContext,
    required this.consentGovernance,
    required this.onConsentChanged,
  });

  @override
  State<IntelligenceScreen> createState() => _IntelligenceScreenState();
}

class _IntelligenceScreenState extends State<IntelligenceScreen> {
  Future<AgenticSynthesis>? _synthesisFuture;
  late bool _consentRiskSignals;
  late bool _consentTreatmentPatterns;
  late bool _consentClinicalContext;
  late bool _consentGovernance;

  @override
  void initState() {
    super.initState();
    _consentRiskSignals = widget.consentRiskSignals;
    _consentTreatmentPatterns = widget.consentTreatmentPatterns;
    _consentClinicalContext = widget.consentClinicalContext;
    _consentGovernance = widget.consentGovernance;
    _loadSynthesis(); 
  }

  Future<void> _loadSynthesis({bool forceRefresh = false}) async {
    setState(() {
      _synthesisFuture = ApiService.getAgenticSynthesis(widget.abhaId, 
        refresh: forceRefresh,
        consent: {
          'risk_signals': _consentRiskSignals,
          'treatment_patterns': _consentTreatmentPatterns,
          'clinical_context': _consentClinicalContext,
          'consent_status': _consentGovernance,
        }
      );
    }); // logic untouched [cite: 5, 6]
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agentic Synthesis'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadSynthesis(forceRefresh: true),
          ),
        ],
      ),
      body: FutureBuilder<AgenticSynthesis>(
        future: _synthesisFuture,
        builder: (context, snapshot) {
          final isLoading = snapshot.connectionState == ConnectionState.waiting;
          final synthesis = snapshot.data;
          final errorMessage = snapshot.hasError
              ? snapshot.error.toString().replaceAll('Exception: ', '')
              : ''; // logic untouched [cite: 8]
          
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            children: [
              _buildConsentCard(),
              const SizedBox(height: 12),
              // Feedback for refresh
              if (_synthesisFuture != null && !isLoading)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _loadSynthesis(forceRefresh: true),
                    icon: const Icon(Icons.auto_awesome, size: 14, color: NexusTheme.accentTeal),
                    label: const Text('Regenerate AI Analysis', style: TextStyle(fontSize: 11, color: NexusTheme.accentTeal)),
                  ),
                ),
              
              if (errorMessage.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.red.shade100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Failed to load intelligence', 
                        style: TextStyle(fontWeight: FontWeight.w900, color: Colors.red)),
                      const SizedBox(height: 8),
                      Text(errorMessage, style: TextStyle(color: Colors.red.shade700)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadSynthesis,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade400),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),

              // UI Update: Wrapped sections in stylized logic [cite: 14-30]
              if (_consentRiskSignals) ...[
                isLoading || synthesis == null
                    ? _buildLoadingSection('Risk Signals', Icons.warning_amber_rounded, Colors.redAccent)
                    : _buildSection(
                        title: 'Risk Signals',
                        icon: Icons.warning_amber_rounded,
                        color: Colors.redAccent,
                        items: synthesis.riskSignals,
                        emptyText: 'No notable risks detected.',
                        showRiskBadge: true,
                      ),
                const SizedBox(height: 16),
              ],
              
              if (_consentTreatmentPatterns) ...[
                isLoading || synthesis == null
                    ? _buildLoadingSection('Treatment Patterns', Icons.trending_up, Colors.blueAccent)
                    : _buildSection(
                        title: 'Treatment Patterns',
                        icon: Icons.trending_up,
                        color: Colors.blueAccent,
                        items: synthesis.treatmentPatterns,
                        emptyText: 'No patterns detected.',
                        useArrowList: true,
                      ),
                const SizedBox(height: 16),
              ],

              if (_consentClinicalContext) ...[
                isLoading || synthesis == null
                    ? _buildLoadingSection('Clinical Context', Icons.local_hospital, NexusTheme.primaryBlue)
                    : _buildTextSection(
                        title: 'Clinical Context',
                        icon: Icons.local_hospital,
                        color: NexusTheme.primaryBlue,
                        text: synthesis.clinicalContext,
                      ),
                const SizedBox(height: 16),
              ],

              if (_consentGovernance) ...[
                isLoading || synthesis == null
                    ? _buildLoadingSection('Governance', Icons.verified_user, NexusTheme.accentTeal)
                    : _buildTextSection(
                        title: 'Governance',
                        icon: Icons.verified_user,
                        color: NexusTheme.accentTeal,
                        text: synthesis.consentStatus,
                      ),
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: NexusTheme.primaryBlue.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Text(
                      '🔒 Zero-Knowledge Agentic Protocol Active',
                      style: TextStyle(color: NexusTheme.textLight, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildConsentCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        children: [
          _buildCustomSwitch(
            title: 'Risk Signals',
            subtitle: 'AI Risk alerts',
            value: _consentRiskSignals,
            icon: Icons.warning_rounded,
            onChanged: (val) {
              setState(() => _consentRiskSignals = val);
              widget.onConsentChanged(_consentRiskSignals, _consentTreatmentPatterns, _consentClinicalContext, _consentGovernance);
            },
          ),
          const Divider(height: 1, indent: 70),
          _buildCustomSwitch(
            title: 'Treatment Patterns',
            subtitle: 'Pattern insights',
            value: _consentTreatmentPatterns,
            icon: Icons.auto_graph_rounded,
            onChanged: (val) {
              setState(() => _consentTreatmentPatterns = val);
              widget.onConsentChanged(_consentRiskSignals, _consentTreatmentPatterns, _consentClinicalContext, _consentGovernance);
            },
          ),
          const Divider(height: 1, indent: 70),
          _buildCustomSwitch(
            title: 'Clinical Context',
            subtitle: 'Summary insights',
            value: _consentClinicalContext,
            icon: Icons.psychology_outlined,
            onChanged: (val) {
              setState(() => _consentClinicalContext = val);
              widget.onConsentChanged(_consentRiskSignals, _consentTreatmentPatterns, _consentClinicalContext, _consentGovernance);
            },
          ),
          const Divider(height: 1, indent: 70),
          _buildCustomSwitch(
            title: 'Governance',
            subtitle: 'Compliance status',
            value: _consentGovernance,
            icon: Icons.gavel_rounded,
            onChanged: (val) {
              setState(() => _consentGovernance = val);
              widget.onConsentChanged(_consentRiskSignals, _consentTreatmentPatterns, _consentClinicalContext, _consentGovernance);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCustomSwitch({
    required String title, 
    required String subtitle, 
    required bool value, 
    required IconData icon, 
    required Function(bool) onChanged
  }) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: NexusTheme.textLight)),
      value: value,
      activeColor: NexusTheme.accentTeal,
      secondary: Icon(icon, color: NexusTheme.primaryBlue.withOpacity(0.7)),
      onChanged: onChanged,
    );
  }

  Widget _buildLoadingSection(String title, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 20),
          LinearProgressIndicator(
            backgroundColor: color.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
            borderRadius: BorderRadius.circular(10),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<String> items,
    required String emptyText,
    bool showRiskBadge = false,
    bool useArrowList = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: color.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18))),
              if (showRiskBadge && items.isNotEmpty) _buildPulsingBadge('High Risk'),
            ],
          ),
          const SizedBox(height: 20),
          if (items.isEmpty)
            Text(emptyText, style: const TextStyle(color: NexusTheme.textLight))
          else
            ...(useArrowList
                ? items.map((item) => _buildPatternRow(item)).toList()
                : items.map((item) => _buildBullet(item)).toList()),
        ],
      ),
    );
  }

  Widget _buildTextSection({
    required String title,
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: color.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ],
          ),
          const SizedBox(height: 16),
          Text(text, style: const TextStyle(color: NexusTheme.textDark, height: 1.6, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _buildPulsingBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
      ),
      child: Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.redAccent)),
    );
  }

  Widget _buildBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.only(top: 8), child: CircleAvatar(radius: 3, backgroundColor: NexusTheme.primaryBlue)),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
        ],
      ),
    );
  }

  Widget _buildPatternRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.arrow_right_alt, size: 20, color: Colors.blueAccent),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
        ],
      ),
    );
  }
}