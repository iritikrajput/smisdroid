import 'url_resolver.dart';
import 'dns_analyzer.dart';
import 'whois_analyzer.dart';
import 'domain_scorer.dart';

/// Master entry point — call this with a raw SMS message.
/// Returns full intelligence report for all URLs found.
class DomainIntelligence {
  static Future<DomainIntelligenceReport> analyze(String message) async {
    // Step 1: Extract all URLs
    final urls = UrlResolver.extractUrls(message);

    if (urls.isEmpty) {
      return DomainIntelligenceReport(
        results: [],
        hasUrls: false,
        highestScore: 0,
        summary: 'No URLs found in message.',
      );
    }

    // Step 2: Analyze each URL in parallel
    final futures = urls.map((url) => _analyzeUrl(url));
    final results = await Future.wait(futures);

    final sorted = results..sort((a, b) => b.score.compareTo(a.score));
    final highest = sorted.isEmpty ? 0 : sorted.first.score;

    return DomainIntelligenceReport(
      results: sorted,
      hasUrls: true,
      highestScore: highest,
      summary: _buildSummary(sorted),
    );
  }

  static Future<DomainScore> _analyzeUrl(String url) async {
    // Step 1: Resolve redirect chain
    final redirect = await UrlResolver.resolveRedirectChain(url);
    final domain = redirect.finalDomain;

    // Step 2: DNS + WHOIS in parallel
    final results = await Future.wait([
      DnsAnalyzer.analyze(domain),
      WhoisAnalyzer.lookup(domain),
    ]);

    final dns   = results[0] as DnsAnalysisResult;
    final whois = results[1] as WhoisResult;

    // Step 3: Score the domain
    var domainScore = DomainScorer.calculate(
      redirect: redirect,
      dns: dns,
      whois: whois,
    );

    // Step 4: Lookup hosting provider from first IP (non-blocking)
    if (dns.ipAddresses.isNotEmpty) {
      try {
        final hosting = await DnsAnalyzer.lookupHosting(dns.ipAddresses.first);
        domainScore = DomainScore(
          domain: domainScore.domain,
          originalUrl: domainScore.originalUrl,
          finalUrl: domainScore.finalUrl,
          score: domainScore.score,
          indicators: domainScore.indicators,
          ipAddresses: domainScore.ipAddresses,
          nameservers: domainScore.nameservers,
          hasMxRecord: domainScore.hasMxRecord,
          hasSPF: domainScore.hasSPF,
          hasDMARC: domainScore.hasDMARC,
          rawDnsRecords: domainScore.rawDnsRecords,
          registrar: domainScore.registrar,
          domainAge: domainScore.domainAge,
          createdDate: domainScore.createdDate,
          expiresDate: domainScore.expiresDate,
          statusFlags: domainScore.statusFlags,
          hostingProvider: hosting.org,
          hostingIsp: hosting.isp,
          hostingAsn: hosting.asn,
          hostingCountry: hosting.country,
          isHostingProvider: hosting.isHosting,
        );
      } catch (_) {
        // Hosting lookup failed — non-critical, continue with defaults
      }
    }

    return domainScore;
  }

  static String _buildSummary(List<DomainScore> results) {
    if (results.isEmpty) return 'No URLs analyzed.';
    final top = results.first;
    return '${results.length} URL(s) analyzed. '
        'Highest risk: ${top.domain} — Score ${top.score}/100 (${top.riskLevel})';
  }
}

class DomainIntelligenceReport {
  final List<DomainScore> results;
  final bool hasUrls;
  final int highestScore;
  final String summary;

  DomainIntelligenceReport({
    required this.results,
    required this.hasUrls,
    required this.highestScore,
    required this.summary,
  });
}
