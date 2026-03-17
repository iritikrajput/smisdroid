class RuleEngine {
  // Weighted keyword categories
  static const Map<String, int> _urgencyKeywords = {
    'urgent': 15,
    'immediately': 15,
    'today': 10,
    'within hours': 20,
    'last chance': 20,
    'expire': 15,
    'final notice': 25,
    'act now': 20,
    'right now': 15,
  };

  static const Map<String, int> _paymentKeywords = {
    'pay': 10,
    'payment': 10,
    'bill': 8,
    'amount due': 20,
    'outstanding': 15,
    'transfer': 10,
    'upi': 12,
    'rupees': 8,
  };

  static const Map<String, int> _threatKeywords = {
    'disconnect': 20,
    'disconnected': 20,
    'suspend': 18,
    'block': 15,
    'deactivate': 18,
    'terminated': 20,
    'cut off': 20,
    'service stopped': 25,
  };

  static const Map<String, int> _verificationKeywords = {
    'verify': 12,
    'kyc': 20,
    'update details': 15,
    'confirm your': 12,
    'validate': 12,
    'authenticate': 15,
  };

  static RuleAnalysisResult analyze(String text) {
    final lowerText = text.toLowerCase();
    int score = 0;
    final List<String> triggered = [];

    void checkCategory(Map<String, int> keywords, String category) {
      for (final entry in keywords.entries) {
        if (lowerText.contains(entry.key)) {
          score += entry.value;
          triggered.add('[$category] "${entry.key}"');
        }
      }
    }

    checkCategory(_urgencyKeywords, 'Urgency');
    checkCategory(_paymentKeywords, 'Payment');
    checkCategory(_threatKeywords, 'Threat');
    checkCategory(_verificationKeywords, 'Verification');

    // High-risk combinations bonus
    final hasUrgency = triggered.any((t) => t.contains('Urgency'));
    final hasPayment = triggered.any((t) => t.contains('Payment'));
    final hasThreat = triggered.any((t) => t.contains('Threat'));

    if (hasUrgency && hasPayment && hasThreat) {
      score += 40; // Critical combination
      triggered.add('[COMBO] Urgency + Payment + Threat detected');
    } else if (hasUrgency && hasPayment) {
      score += 20;
      triggered.add('[COMBO] Urgency + Payment detected');
    }

    return RuleAnalysisResult(
      score: score.clamp(0, 100),
      triggeredRules: triggered,
    );
  }
}

class RuleAnalysisResult {
  final int score;
  final List<String> triggeredRules;
  RuleAnalysisResult({required this.score, required this.triggeredRules});
}
