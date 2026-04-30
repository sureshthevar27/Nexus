class AgenticSynthesis {
  final List<String> riskSignals;
  final List<String> treatmentPatterns;
  final String clinicalContext;
  final String consentStatus;

  const AgenticSynthesis({
    required this.riskSignals,
    required this.treatmentPatterns,
    required this.clinicalContext,
    required this.consentStatus,
  });

  factory AgenticSynthesis.fromJson(Map<String, dynamic> json) {
    return AgenticSynthesis(
      riskSignals: _stringList(json['risk_signals']),
      treatmentPatterns: _stringList(json['treatment_patterns']),
      clinicalContext: _stringValue(json['clinical_context']) ?? 'No notable findings.',
      consentStatus: _stringValue(json['consent_status']) ?? 'No notable findings.',
    );
  }

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.whereType<String>().map((item) => item.trim()).where((item) => item.isNotEmpty).toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      return [value.trim()];
    }
    return [];
  }

  static String? _stringValue(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}
