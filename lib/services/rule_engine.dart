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

  /// Classify the fraud subtype based on message content patterns.
  /// Called only when a message is classified as FRAUD or SUSPICIOUS.
  static String classifyFraudType(String text, List<String> urls) {
    final t = text.toLowerCase();
    int kycScore = 0;
    int impersonationScore = 0;
    int phishingScore = 0;
    int paymentScore = 0;
    int blockScore = 0;

    // ── Account Block Scam signals ──
    if (RegExp(r'account.{0,10}(blocked|frozen|suspended|deactivated|locked|restricted)').hasMatch(t)) blockScore += 5;
    if (RegExp(r'(freeze|suspend|block|lock).{0,10}(account|card|banking)').hasMatch(t)) blockScore += 4;
    if (t.contains('temporarily blocked') || t.contains('access denied')) blockScore += 4;
    if (t.contains('net banking') && (t.contains('expire') || t.contains('locked'))) blockScore += 3;

    // ── KYC Scam signals ──
    if (t.contains('kyc')) kycScore += 5;
    if (t.contains('aadhaar') || t.contains('aadhar')) kycScore += 4;
    if (t.contains('pan card') || t.contains('pan update') || t.contains('pan verif')) kycScore += 4;
    if (t.contains('identity verification') || t.contains('verify identity')) kycScore += 3;
    if (t.contains('update your details') || t.contains('update details')) kycScore += 3;
    if (t.contains('know your customer')) kycScore += 5;

    // ── Impersonation signals ──
    const banks = ['sbi', 'hdfc', 'icici', 'axis', 'kotak', 'pnb', 'boi', 'bob',
        'canara', 'union bank', 'yes bank', 'indusind', 'rbi', 'federal bank'];
    const utilities = ['bescom', 'mahadiscom', 'adani', 'tata power', 'torrent power',
        'cesc', 'bses', 'hpcl', 'bpcl', 'indane', 'bharat gas', 'irctc', 'epfo'];
    const telecoms = ['airtel', 'jio', 'vodafone', 'bsnl', 'vi '];
    for (final name in [...banks, ...utilities, ...telecoms]) {
      if (t.contains(name)) {
        impersonationScore += 3;
        break;
      }
    }
    if (RegExp(r'(security|alert|notice|warning)\s*:').hasMatch(t)) impersonationScore += 2;
    if (t.contains('dear customer') || t.contains('valued customer')) impersonationScore += 2;

    // ── Fake Payment Portal signals ──
    if (RegExp(r'pay\s*(now|at|online|immediately|before|via|using|through)').hasMatch(t)) paymentScore += 4;
    if (t.contains('pending bill') || t.contains('pending dues') || t.contains('amount due')) paymentScore += 4;
    if (t.contains('overdue') || t.contains('outstanding')) paymentScore += 3;
    if (RegExp(r'rs\.?\s*\d+').hasMatch(t)) paymentScore += 2;
    if (t.contains('complete payment') || t.contains('bill payment')) paymentScore += 3;

    // ── Phishing Link signals ──
    if (urls.isNotEmpty) phishingScore += 2;
    for (final url in urls) {
      final u = url.toLowerCase();
      if (RegExp(r'\.\d{1,3}\.\d{1,3}\.\d{1,3}').hasMatch(u)) phishingScore += 3; // IP URL
      if (RegExp(r'\.(xyz|tk|ml|cf|ga|top|click|buzz|vip|sbs|cfd)').hasMatch(u)) phishingScore += 3;
      if (u.contains('bit.ly') || u.contains('tinyurl') || u.contains('cutt.ly') || u.contains('tiny.one')) phishingScore += 2;
      if (RegExp(r'hxxp|%3A%2F|\(\.\)').hasMatch(u)) phishingScore += 3; // obfuscated
    }

    // Pick highest scoring type
    final scores = {
      'account_block_scam': blockScore,
      'kyc_scam': kycScore,
      'impersonation': impersonationScore,
      'fake_payment_portal': paymentScore,
      'phishing_link': phishingScore,
    };

    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Only classify if there's a clear signal (score > 0)
    if (sorted.first.value > 0) {
      return sorted.first.key;
    }

    // Fallback: if has URL → phishing, otherwise generic
    return urls.isNotEmpty ? 'phishing_link' : 'impersonation';
  }
}

class RuleAnalysisResult {
  final int score;
  final List<String> triggeredRules;
  RuleAnalysisResult({required this.score, required this.triggeredRules});
}
