import 'dart:convert';
import 'package:http/http.dart' as http;

/// WHOIS analysis via rdap.org (free, no API key needed)
/// RDAP = Registration Data Access Protocol — modern WHOIS replacement
/// Returns: registrar name, creation date, expiry, domain age in days
class WhoisAnalyzer {
  // RDAP bootstrap endpoint — queries the correct RDAP server per TLD automatically
  static const String _rdapBase = 'https://rdap.org/domain/';
  static const Duration _timeout = Duration(seconds: 8);

  static Future<WhoisResult> lookup(String domain) async {
    try {
      final response = await http
          .get(Uri.parse('$_rdapBase$domain'))
          .timeout(_timeout);

      if (response.statusCode != 200) {
        return WhoisResult.unavailable(domain);
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return _parseRdap(domain, data);
    } catch (_) {
      return WhoisResult.unavailable(domain);
    }
  }

  static WhoisResult _parseRdap(String domain, Map<String, dynamic> data) {
    String? registrar;
    DateTime? createdDate;
    DateTime? expiresDate;
    DateTime? updatedDate;

    // ── Extract registrar ──────────────────────────────────────
    final entities = data['entities'] as List<dynamic>? ?? [];
    for (final entity in entities) {
      final roles = (entity['roles'] as List<dynamic>?) ?? [];
      if (roles.contains('registrar')) {
        final vcardArray = entity['vcardArray'] as List<dynamic>?;
        if (vcardArray != null && vcardArray.length > 1) {
          final vcardProps = vcardArray[1] as List<dynamic>;
          for (final prop in vcardProps) {
            if (prop is List && prop[0] == 'fn') {
              registrar = prop[3] as String?;
              break;
            }
          }
        }
        // Fallback to publicIds
        if (registrar == null) {
          registrar = entity['handle'] as String?;
        }
      }
    }

    // ── Extract dates from events array ───────────────────────
    final events = data['events'] as List<dynamic>? ?? [];
    for (final event in events) {
      final action = event['eventAction'] as String? ?? '';
      final dateStr = event['eventDate'] as String? ?? '';
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;

      if (action == 'registration') createdDate = date;
      if (action == 'expiration') expiresDate = date;
      if (action == 'last changed') updatedDate = date;
    }

    // ── Calculate domain age ──────────────────────────────────
    final now = DateTime.now();
    final ageDays = createdDate != null
        ? now.difference(createdDate).inDays
        : null;

    final daysUntilExpiry = expiresDate != null
        ? expiresDate.difference(now).inDays
        : null;

    // ── Status flags ──────────────────────────────────────────
    final statusList = (data['status'] as List<dynamic>?)
            ?.map((s) => s.toString())
            .toList() ?? [];

    return WhoisResult(
      domain: domain,
      registrar: registrar ?? 'Unknown',
      createdDate: createdDate,
      expiresDate: expiresDate,
      updatedDate: updatedDate,
      ageDays: ageDays,
      daysUntilExpiry: daysUntilExpiry,
      statusFlags: statusList,
      isAvailable: false,
      dataAvailable: true,
    );
  }
}

class WhoisResult {
  final String domain;
  final String registrar;
  final DateTime? createdDate;
  final DateTime? expiresDate;
  final DateTime? updatedDate;
  final int? ageDays;
  final int? daysUntilExpiry;
  final List<String> statusFlags;
  final bool isAvailable;
  final bool dataAvailable;

  WhoisResult({
    required this.domain,
    required this.registrar,
    required this.createdDate,
    required this.expiresDate,
    required this.updatedDate,
    required this.ageDays,
    required this.daysUntilExpiry,
    required this.statusFlags,
    required this.isAvailable,
    required this.dataAvailable,
  });

  factory WhoisResult.unavailable(String domain) => WhoisResult(
        domain: domain,
        registrar: 'Unavailable',
        createdDate: null,
        expiresDate: null,
        updatedDate: null,
        ageDays: null,
        daysUntilExpiry: null,
        statusFlags: [],
        isAvailable: false,
        dataAvailable: false,
      );

  // ── Risk helpers ──────────────────────────────────────────────
  bool get isNewlyRegistered => ageDays != null && ageDays! < 30;
  bool get isVeryNew         => ageDays != null && ageDays! < 7;
  bool get expiresVySoon     => daysUntilExpiry != null && daysUntilExpiry! < 30;

  String get ageDescription {
    if (ageDays == null) return 'Unknown';
    if (ageDays! < 1) return 'Registered today';
    if (ageDays! < 7) return '$ageDays days old';
    if (ageDays! < 30) return '${(ageDays! / 7).floor()} weeks old';
    if (ageDays! < 365) return '${(ageDays! / 30).floor()} months old';
    return '${(ageDays! / 365).floor()} years old';
  }
}
