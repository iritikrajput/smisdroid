import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Performs DNS record lookups using DNS-over-HTTPS (DoH)
/// Works on both Android and iOS without native bindings.
/// Checks: A records (IP), MX records, TXT records (SPF), NS records
class DnsAnalyzer {
  // Cloudflare DoH endpoint — no tracking, works globally
  static const String _dohUrl = 'https://cloudflare-dns.com/dns-query';
  static const Duration _timeout = Duration(seconds: 5);

  // ── Query DNS record types ────────────────────────────────────
  static Future<DnsRecord?> _queryDoH(String domain, String type) async {
    try {
      final response = await http.get(
        Uri.parse('$_dohUrl?name=$domain&type=$type'),
        headers: {'Accept': 'application/dns-json'},
      ).timeout(_timeout);

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final status = data['Status'] as int? ?? 3;
      final answers = (data['Answer'] as List<dynamic>?) ?? [];

      return DnsRecord(
        type: type,
        domain: domain,
        status: status,
        answers: answers
            .map((a) => DnsAnswer(
                  type: a['type'] as int? ?? 0,
                  ttl: a['TTL'] as int? ?? 0,
                  data: a['data'] as String? ?? '',
                ))
            .toList(),
        exists: status == 0 && answers.isNotEmpty,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Full DNS analysis for one domain ─────────────────────────
  static Future<DnsAnalysisResult> analyze(String domain) async {
    // Parallel queries for speed
    final results = await Future.wait([
      _queryDoH(domain, 'A'),     // IPv4 address
      _queryDoH(domain, 'AAAA'),  // IPv6 address
      _queryDoH(domain, 'MX'),    // Mail exchange
      _queryDoH(domain, 'TXT'),   // SPF / DMARC
      _queryDoH(domain, 'NS'),    // Nameservers
    ]);

    final aRecord  = results[0];
    final aaaaRec  = results[1];
    final mxRecord = results[2];
    final txtRecord= results[3];
    final nsRecord = results[4];

    // Extract IP addresses
    final List<String> ipAddresses = [];
    for (final ans in aRecord?.answers ?? []) {
      ipAddresses.add(ans.data);
    }
    for (final ans in aaaaRec?.answers ?? []) {
      ipAddresses.add(ans.data);
    }

    // Check SPF record
    final hasSPF = txtRecord?.answers.any(
          (a) => a.data.contains('v=spf1')) ?? false;

    // Check DMARC
    final hasDMARC = txtRecord?.answers.any(
          (a) => a.data.contains('v=DMARC1')) ?? false;

    // Extract nameservers
    final nameservers = nsRecord?.answers
            .map((a) => a.data.replaceAll(RegExp(r'\.$'), ''))
            .toList() ?? [];

    // Suspicious nameserver detection
    final suspiciousNS = _detectSuspiciousNameservers(nameservers);

    // Domain exists check
    final domainExists = aRecord?.exists ?? false;

    // Free hosting / bulletproof hosting check
    final isOnFreeHosting = _checkFreeHosting(nameservers, ipAddresses);

    return DnsAnalysisResult(
      domain: domain,
      ipAddresses: ipAddresses,
      hasMxRecord: mxRecord?.exists ?? false,
      hasSPF: hasSPF,
      hasDMARC: hasDMARC,
      nameservers: nameservers,
      suspiciousNameservers: suspiciousNS,
      domainExists: domainExists,
      isOnFreeHosting: isOnFreeHosting,
      rawRecords: {
        'A': aRecord?.answers.map((a) => a.data).toList() ?? [],
        'MX': mxRecord?.answers.map((a) => a.data).toList() ?? [],
        'TXT': txtRecord?.answers.map((a) => a.data).toList() ?? [],
        'NS': nameservers,
      },
    );
  }

  static List<String> _detectSuspiciousNameservers(List<String> ns) {
    // Known bulletproof / frequently abused hosting nameservers
    const suspicious = [
      'namecheap', 'freenom', 'topdns', 'cloudns',
      'afraid.org', 'dynu', 'changeip',
    ];
    return ns.where((n) {
      final lower = n.toLowerCase();
      return suspicious.any((s) => lower.contains(s));
    }).toList();
  }

  static bool _checkFreeHosting(List<String> ns, List<String> ips) {
    const freeHostingNS = ['freenom', 'afraid.org', '000webhost', 'byethost'];
    // Known Freenom IP ranges (simplified)
    const suspiciousIpPrefixes = ['197.231', '154.70', '41.215'];

    final nsMatch = ns.any((n) => freeHostingNS.any((f) => n.contains(f)));
    final ipMatch = ips.any((ip) => suspiciousIpPrefixes.any((p) => ip.startsWith(p)));
    return nsMatch || ipMatch;
  }
}

// ── Data models ───────────────────────────────────────────────

class DnsRecord {
  final String type;
  final String domain;
  final int status;
  final List<DnsAnswer> answers;
  final bool exists;

  DnsRecord({
    required this.type,
    required this.domain,
    required this.status,
    required this.answers,
    required this.exists,
  });
}

class DnsAnswer {
  final int type;
  final int ttl;
  final String data;
  DnsAnswer({required this.type, required this.ttl, required this.data});
}

class DnsAnalysisResult {
  final String domain;
  final List<String> ipAddresses;
  final bool hasMxRecord;
  final bool hasSPF;
  final bool hasDMARC;
  final List<String> nameservers;
  final List<String> suspiciousNameservers;
  final bool domainExists;
  final bool isOnFreeHosting;
  final Map<String, List<String>> rawRecords;

  DnsAnalysisResult({
    required this.domain,
    required this.ipAddresses,
    required this.hasMxRecord,
    required this.hasSPF,
    required this.hasDMARC,
    required this.nameservers,
    required this.suspiciousNameservers,
    required this.domainExists,
    required this.isOnFreeHosting,
    required this.rawRecords,
  });

  /// Domains used purely for phishing rarely have MX or SPF records
  bool get hasSuspiciousDnsProfile => !hasMxRecord && !hasSPF && !hasDMARC;
}
