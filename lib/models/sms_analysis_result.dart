class SmsAnalysisResult {
  final String originalMessage;
  final String sender;
  final String riskLevel; // SAFE / SUSPICIOUS / FRAUD
  final double riskScore; // 0.0 - 1.0
  final String fraudType; // benign / kyc_scam / impersonation / phishing_link / fake_payment_portal / account_block_scam
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
    this.fraudType = 'benign',
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
    'fraud_type': fraudType,
    'urls': detectedUrls.join(','),
    'rules': triggeredRules.join('|'),
    'domain_score': domainScore,
    'nlp_score': nlpScore,
    'timestamp': timestamp.toIso8601String(),
  };

  bool get isFraud => riskLevel == 'FRAUD';
  bool get isSuspicious => riskLevel == 'SUSPICIOUS';

  /// Human-readable fraud type label
  String get fraudTypeLabel {
    switch (fraudType) {
      case 'kyc_scam': return 'KYC Scam';
      case 'impersonation': return 'Impersonation';
      case 'phishing_link': return 'Phishing Link';
      case 'fake_payment_portal': return 'Fake Payment Portal';
      case 'account_block_scam': return 'Account Block Scam';
      default: return 'Benign';
    }
  }
}
