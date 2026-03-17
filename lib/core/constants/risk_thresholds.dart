class RiskThresholds {
  RiskThresholds._();

  // Final Risk Score Thresholds (0.0 - 1.0)
  static const double safeMaxThreshold = 0.3;
  static const double suspiciousMaxThreshold = 0.6;
  // Above 0.6 is FRAUD

  // Component Weight Distribution (must sum to 1.0)
  static const double nlpWeight = 0.40;
  static const double domainWeight = 0.35;
  static const double ruleWeight = 0.25;

  // Domain Score Thresholds (0 - 100)
  static const int domainSafeMax = 25;
  static const int domainSuspiciousMax = 50;
  // Above 50 is high risk

  // NLP Score Thresholds (0.0 - 1.0)
  static const double nlpSafeMax = 0.3;
  static const double nlpSuspiciousMax = 0.6;

  // Rule Engine Score Thresholds (0 - 100)
  static const int ruleSafeMax = 20;
  static const int ruleSuspiciousMax = 50;

  // Domain Age Risk (in days)
  static const int domainVeryNewDays = 7;
  static const int domainNewDays = 30;
  static const int domainYoungDays = 90;

  // Redirect Chain Risk
  static const int maxSafeRedirects = 2;
  static const int maxSuspiciousRedirects = 4;

  // URL Shortener Handling
  static const bool flagUrlShorteners = true;
  static const int urlShortenerPenalty = 15;

  // Trusted Sender Boost
  static const double trustedSenderDiscount = 0.5;

  // Helper method to get risk level from final score
  static String getRiskLevel(double score) {
    if (score <= safeMaxThreshold) {
      return 'SAFE';
    } else if (score <= suspiciousMaxThreshold) {
      return 'SUSPICIOUS';
    } else {
      return 'FRAUD';
    }
  }

  // Normalize domain score (0-100) to (0.0-1.0)
  static double normalizeDomainScore(int score) {
    return (score / 100.0).clamp(0.0, 1.0);
  }

  // Normalize rule score (0-100) to (0.0-1.0)
  static double normalizeRuleScore(int score) {
    return (score / 100.0).clamp(0.0, 1.0);
  }
}
