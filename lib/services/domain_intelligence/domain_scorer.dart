import 'dart:math';
import 'url_resolver.dart';
import 'dns_analyzer.dart';
import 'whois_analyzer.dart';

/// Combines all signals into a 0–100 risk score with full explanation
class DomainScorer {
  static const List<String> _suspiciousTLDs = [
    '.xyz', '.top', '.tk', '.ml', '.cf', '.ga', '.gq',
    '.pw', '.buzz', '.click', '.link', '.stream',
    '.download', '.loan', '.win', '.review', '.party',
  ];

  static const List<String> _trustedBrands = [
    'sbi', 'hdfc', 'icici', 'axis', 'adani', 'tata', 'reliance',
    'bsnl', 'airtel', 'jio', 'paytm', 'phonepe', 'googlepay',
    'mahadiscom', 'bescom', 'torrent', 'cesc',
  ];

  /// Legitimate domains for typosquatting comparison
  static const List<String> _legitimateDomains = [
    'sbi.co.in', 'onlinesbi.sbi', 'hdfcbank.com', 'icicibank.com',
    'axisbank.com', 'kotak.com', 'yesbank.in', 'bankofbaroda.in',
    'pnbindia.in', 'adanielectricity.com', 'tatpower.com',
    'bescom.co.in', 'mahadiscom.in', 'airtel.in', 'jio.com',
    'paytm.com', 'phonepe.com', 'googlepay.com', 'amazonpay.in',
    'irctc.co.in', 'incometax.gov.in', 'epfindia.gov.in',
  ];

  /// Homograph character map: confusable Unicode → Latin equivalent
  static const Map<int, String> _homoglyphs = {
    // Cyrillic
    0x0430: 'a', 0x0435: 'e', 0x043E: 'o', 0x0440: 'p',
    0x0441: 'c', 0x0443: 'y', 0x0445: 'x', 0x0456: 'i',
    0x0455: 's', 0x0458: 'j', 0x04BB: 'h', 0x0432: 'b',
    // Greek
    0x03BF: 'o', 0x03BD: 'v', 0x03C4: 't', 0x03B1: 'a',
    0x03B5: 'e', 0x03BA: 'k', 0x03B9: 'i',
  };

  static DomainScore calculate({
    required RedirectChainResult redirect,
    required DnsAnalysisResult dns,
    required WhoisResult whois,
  }) {
    int score = 0;
    final indicators = <ScoringIndicator>[];

    final domain = redirect.finalDomain.toLowerCase();
    final tld = UrlResolver.extractTld(domain);

    // ── 1. Redirect chain analysis ─────────────────────────────
    if (redirect.wasRedirected) {
      final redirectScore = (redirect.hopCount * 8).clamp(0, 25);
      score += redirectScore;
      indicators.add(ScoringIndicator(
        category: 'Redirect',
        description: '${redirect.hopCount} redirect hop(s): ${redirect.originalUrl} → ${redirect.finalDomain}',
        points: redirectScore,
        severity: redirect.hopCount > 2 ? Severity.high : Severity.medium,
      ));
    }

    // ── 2. TLD reputation ──────────────────────────────────────
    if (_suspiciousTLDs.contains(tld)) {
      score += 25;
      indicators.add(ScoringIndicator(
        category: 'TLD',
        description: 'Suspicious top-level domain: $tld',
        points: 25,
        severity: Severity.high,
      ));
    }

    // ── 3. Domain age (WHOIS) ──────────────────────────────────
    if (whois.isVeryNew) {
      score += 35;
      indicators.add(ScoringIndicator(
        category: 'Domain Age',
        description: 'Domain registered ${whois.ageDescription} via ${whois.registrar}',
        points: 35,
        severity: Severity.critical,
      ));
    } else if (whois.isNewlyRegistered) {
      score += 22;
      indicators.add(ScoringIndicator(
        category: 'Domain Age',
        description: 'Very new domain — ${whois.ageDescription} (Registrar: ${whois.registrar})',
        points: 22,
        severity: Severity.high,
      ));
    }

    // ── 4. Shannon entropy (generated domains) ─────────────────
    final domainName = domain.split('.').first;
    final entropy = _shannonEntropy(domainName);
    if (entropy > 3.8) {
      score += 18;
      indicators.add(ScoringIndicator(
        category: 'Entropy',
        description: 'High domain entropy (${entropy.toStringAsFixed(2)}) — likely algorithmically generated',
        points: 18,
        severity: Severity.medium,
      ));
    }

    // ── 5. Brand impersonation ─────────────────────────────────
    for (final brand in _trustedBrands) {
      if (domain.contains(brand)) {
        score += 30;
        indicators.add(ScoringIndicator(
          category: 'Brand Impersonation',
          description: 'Impersonates "$brand" — not an official domain',
          points: 30,
          severity: Severity.critical,
        ));
        break;
      }
    }

    // ── 6. Homograph / Punycode detection ─────────────────────
    final homographResult = _detectHomographs(domain);
    if (homographResult > 0) {
      score += homographResult;
      indicators.add(ScoringIndicator(
        category: 'Homograph',
        description: 'Suspicious Unicode characters or Punycode detected in domain',
        points: homographResult,
        severity: Severity.critical,
      ));
    }

    // ── 7. Typosquatting (Levenshtein distance) ──────────────
    final typoResult = _detectTyposquatting(domain);
    if (typoResult != null) {
      score += typoResult.points;
      indicators.add(typoResult);
    }

    // ── 7b. Hyphen count (additional typosquatting signal) ───
    final hyphens = domainName.split('-').length - 1;
    if (hyphens >= 2) {
      final pts = (hyphens * 7).clamp(0, 20);
      score += pts;
      indicators.add(ScoringIndicator(
        category: 'Typosquatting',
        description: '$hyphens hyphens in domain name — common typosquatting pattern',
        points: pts,
        severity: Severity.medium,
      ));
    }

    // ── 7. DNS profile ─────────────────────────────────────────
    if (dns.hasSuspiciousDnsProfile) {
      score += 15;
      indicators.add(ScoringIndicator(
        category: 'DNS Profile',
        description: 'No MX, SPF, or DMARC records — typical phishing infrastructure',
        points: 15,
        severity: Severity.medium,
      ));
    }

    if (dns.isOnFreeHosting) {
      score += 20;
      indicators.add(ScoringIndicator(
        category: 'DNS Hosting',
        description: 'Hosted on free/bulletproof hosting — high abuse rate',
        points: 20,
        severity: Severity.high,
      ));
    }

    if (dns.suspiciousNameservers.isNotEmpty) {
      score += 12;
      indicators.add(ScoringIndicator(
        category: 'Nameservers',
        description: 'Suspicious nameservers: ${dns.suspiciousNameservers.join(", ")}',
        points: 12,
        severity: Severity.medium,
      ));
    }

    // ── 8. IP address used directly ───────────────────────────
    if (RegExp(r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}')
        .hasMatch(redirect.finalUrl)) {
      score += 40;
      indicators.add(ScoringIndicator(
        category: 'IP URL',
        description: 'Direct IP address used instead of domain — strong phishing signal',
        points: 40,
        severity: Severity.critical,
      ));
    }

    // ── 9. URL shortener ──────────────────────────────────────
    const shorteners = ['bit.ly', 'tinyurl', 't.co', 'rb.gy', 'ow.ly', 'shorturl.at'];
    if (shorteners.any((s) => redirect.originalUrl.contains(s))) {
      score += 15;
      indicators.add(ScoringIndicator(
        category: 'URL Shortener',
        description: 'URL shortener hides true destination',
        points: 15,
        severity: Severity.medium,
      ));
    }

    return DomainScore(
      domain: redirect.finalDomain,
      originalUrl: redirect.originalUrl,
      finalUrl: redirect.finalUrl,
      score: score.clamp(0, 100),
      indicators: indicators,
      ipAddresses: dns.ipAddresses,
      registrar: whois.registrar,
      domainAge: whois.ageDescription,
      createdDate: whois.createdDate,
      nameservers: dns.nameservers,
    );
  }

  /// Detect homograph attacks (mixed scripts, punycode, confusable chars)
  static int _detectHomographs(String domain) {
    int points = 0;

    // Check for Punycode (xn--)
    if (domain.contains('xn--')) {
      points += 20;
    }

    // Check for homoglyph characters
    bool hasHomoglyph = false;
    bool hasLatin = false;
    for (final rune in domain.runes) {
      if (_homoglyphs.containsKey(rune)) {
        hasHomoglyph = true;
      }
      if ((rune >= 0x0041 && rune <= 0x005A) || (rune >= 0x0061 && rune <= 0x007A)) {
        hasLatin = true;
      }
    }

    // Mixed scripts (Latin + confusable Unicode)
    if (hasHomoglyph && hasLatin) {
      points += 25;
    } else if (hasHomoglyph) {
      points += 15;
    }

    return points;
  }

  /// Detect typosquatting via Levenshtein distance against legitimate domains
  static ScoringIndicator? _detectTyposquatting(String domain) {
    for (final legit in _legitimateDomains) {
      final distance = _levenshteinDistance(domain, legit);
      final maxLen = domain.length > legit.length ? domain.length : legit.length;
      if (maxLen == 0) continue;
      final similarity = 1.0 - (distance / maxLen);

      if (similarity > 0.75 && domain != legit) {
        return ScoringIndicator(
          category: 'Typosquatting',
          description: 'Similar to legitimate "$legit" (${(similarity * 100).toStringAsFixed(0)}% match)',
          points: 30,
          severity: Severity.critical,
        );
      }
    }
    return null;
  }

  /// Levenshtein edit distance between two strings
  static int _levenshteinDistance(String s1, String s2) {
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> prev = List.generate(s2.length + 1, (i) => i);
    List<int> curr = List.filled(s2.length + 1, 0);

    for (int i = 1; i <= s1.length; i++) {
      curr[0] = i;
      for (int j = 1; j <= s2.length; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        curr[j] = [
          prev[j] + 1,
          curr[j - 1] + 1,
          prev[j - 1] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
      final temp = prev;
      prev = curr;
      curr = temp;
    }
    return prev[s2.length];
  }

  static double _shannonEntropy(String text) {
    if (text.isEmpty) return 0;
    final freq = <String, int>{};
    for (final c in text.split('')) {
      freq[c] = (freq[c] ?? 0) + 1;
    }
    double entropy = 0;
    for (final count in freq.values) {
      final p = count / text.length;
      entropy -= p * (log(p) / log(2));
    }
    return entropy;
  }
}

// ── Output Models ─────────────────────────────────────────────

enum Severity { low, medium, high, critical }

class ScoringIndicator {
  final String category;
  final String description;
  final int points;
  final Severity severity;

  ScoringIndicator({
    required this.category,
    required this.description,
    required this.points,
    required this.severity,
  });

  int get severityColorHex {
    switch (severity) {
      case Severity.critical: return 0xFFFF3B30;
      case Severity.high:     return 0xFFFF6B35;
      case Severity.medium:   return 0xFFFF9500;
      case Severity.low:      return 0xFF34C759;
    }
  }
}

class DomainScore {
  final String domain;
  final String originalUrl;
  final String finalUrl;
  final int score;
  final List<ScoringIndicator> indicators;
  final List<String> ipAddresses;
  final String registrar;
  final String domainAge;
  final DateTime? createdDate;
  final List<String> nameservers;

  DomainScore({
    required this.domain,
    required this.originalUrl,
    required this.finalUrl,
    required this.score,
    required this.indicators,
    required this.ipAddresses,
    required this.registrar,
    required this.domainAge,
    required this.createdDate,
    required this.nameservers,
  });

  String get riskLevel {
    if (score >= 60) return 'HIGH RISK';
    if (score >= 30) return 'MEDIUM RISK';
    return 'LOW RISK';
  }
}
