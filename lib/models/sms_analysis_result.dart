class SmsAnalysisResult {
  final String originalMessage;
  final String sender;
  final String riskLevel; // SAFE / SUSPICIOUS / FRAUD
  final double riskScore; // 0.0 - 1.0
  final List<String> detectedUrls;
  final List<String> triggeredRules;
  final int domainScore;
  final double nlpScore;
  final DateTime timestamp;
  final Map<String, dynamic> explanation;

  SmsAnalysisResult({
    required this.originalMessage,
    required this.sender,
    required this.riskLevel,
    required this.riskScore,
    required this.detectedUrls,
    required this.triggeredRules,
    required this.domainScore,
    required this.nlpScore,
    required this.timestamp,
    required this.explanation,
  });

  Map<String, dynamic> toMap() => {
    'message': originalMessage,
    'sender': sender,
    'risk_level': riskLevel,
    'risk_score': riskScore,
    'urls': detectedUrls.join(','),
    'rules': triggeredRules.join(','),
    'domain_score': domainScore,
    'nlp_score': nlpScore,
    'timestamp': timestamp.toIso8601String(),
  };

  bool get isFraud => riskLevel == 'FRAUD';
  bool get isSuspicious => riskLevel == 'SUSPICIOUS';
}
