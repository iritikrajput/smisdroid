class DomainScoreModel {
  final String domain;
  final String originalUrl;
  final String? finalUrl;
  final int score;
  final List<DomainIndicator> indicators;
  final List<String> ipAddresses;
  final String? registrar;
  final String? domainAge;
  final DateTime? createdDate;
  final List<String> nameservers;
  final int redirectHops;
  final bool isUrlShortener;
  final bool hasValidDns;
  final bool hasSecurityRecords;

  DomainScoreModel({
    required this.domain,
    required this.originalUrl,
    this.finalUrl,
    required this.score,
    required this.indicators,
    this.ipAddresses = const [],
    this.registrar,
    this.domainAge,
    this.createdDate,
    this.nameservers = const [],
    this.redirectHops = 0,
    this.isUrlShortener = false,
    this.hasValidDns = true,
    this.hasSecurityRecords = false,
  });

  String get riskLevel {
    if (score <= 25) return 'LOW';
    if (score <= 50) return 'MEDIUM';
    if (score <= 75) return 'HIGH';
    return 'CRITICAL';
  }

  bool get isHighRisk => score > 50;
  bool get isCriticalRisk => score > 75;
  bool get isNewDomain => createdDate != null &&
      DateTime.now().difference(createdDate!).inDays < 30;

  Map<String, dynamic> toJson() {
    return {
      'domain': domain,
      'originalUrl': originalUrl,
      'finalUrl': finalUrl,
      'score': score,
      'indicators': indicators.map((i) => i.toJson()).toList(),
      'ipAddresses': ipAddresses,
      'registrar': registrar,
      'domainAge': domainAge,
      'createdDate': createdDate?.toIso8601String(),
      'nameservers': nameservers,
      'redirectHops': redirectHops,
      'isUrlShortener': isUrlShortener,
      'hasValidDns': hasValidDns,
      'hasSecurityRecords': hasSecurityRecords,
    };
  }

  factory DomainScoreModel.fromJson(Map<String, dynamic> json) {
    return DomainScoreModel(
      domain: json['domain'] as String,
      originalUrl: json['originalUrl'] as String,
      finalUrl: json['finalUrl'] as String?,
      score: json['score'] as int,
      indicators: (json['indicators'] as List<dynamic>)
          .map((i) => DomainIndicator.fromJson(i as Map<String, dynamic>))
          .toList(),
      ipAddresses: List<String>.from(json['ipAddresses'] ?? []),
      registrar: json['registrar'] as String?,
      domainAge: json['domainAge'] as String?,
      createdDate: json['createdDate'] != null
          ? DateTime.parse(json['createdDate'] as String)
          : null,
      nameservers: List<String>.from(json['nameservers'] ?? []),
      redirectHops: json['redirectHops'] as int? ?? 0,
      isUrlShortener: json['isUrlShortener'] as bool? ?? false,
      hasValidDns: json['hasValidDns'] as bool? ?? true,
      hasSecurityRecords: json['hasSecurityRecords'] as bool? ?? false,
    );
  }
}

class DomainIndicator {
  final String category;
  final String description;
  final int points;
  final IndicatorSeverity severity;

  DomainIndicator({
    required this.category,
    required this.description,
    required this.points,
    required this.severity,
  });

  Map<String, dynamic> toJson() {
    return {
      'category': category,
      'description': description,
      'points': points,
      'severity': severity.name,
    };
  }

  factory DomainIndicator.fromJson(Map<String, dynamic> json) {
    return DomainIndicator(
      category: json['category'] as String,
      description: json['description'] as String,
      points: json['points'] as int,
      severity: IndicatorSeverity.values.firstWhere(
        (e) => e.name == json['severity'],
        orElse: () => IndicatorSeverity.low,
      ),
    );
  }
}

enum IndicatorSeverity {
  low,
  medium,
  high,
  critical,
}
