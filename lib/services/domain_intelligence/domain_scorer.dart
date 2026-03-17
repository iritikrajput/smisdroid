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

    // ── 6. Hyphen count (typosquatting) ────────────────────────
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

  Color get severityColor {
    switch (severity) {
      case Severity.critical: return const Color(0xFFFF3B30);
      case Severity.high:     return const Color(0xFFFF6B35);
      case Severity.medium:   return const Color(0xFFFF9500);
      case Severity.low:      return const Color(0xFF34C759);
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
