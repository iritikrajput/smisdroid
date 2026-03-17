class NlpResult {
  final String inputText;
  final double fraudProbability;
  final double confidence;
  final String classification;
  final List<NlpFeature> detectedFeatures;
  final int processingTimeMs;
  final bool usedFallback;

  NlpResult({
    required this.inputText,
    required this.fraudProbability,
    required this.confidence,
    required this.classification,
    this.detectedFeatures = const [],
    this.processingTimeMs = 0,
    this.usedFallback = false,
  });

  bool get isFraud => fraudProbability > 0.5;
  bool get isHighConfidence => confidence > 0.8;

  String get riskLevel {
    if (fraudProbability <= 0.3) return 'LOW';
    if (fraudProbability <= 0.6) return 'MEDIUM';
    if (fraudProbability <= 0.8) return 'HIGH';
    return 'CRITICAL';
  }

  Map<String, dynamic> toJson() {
    return {
      'inputText': inputText,
      'fraudProbability': fraudProbability,
      'confidence': confidence,
      'classification': classification,
      'detectedFeatures': detectedFeatures.map((f) => f.toJson()).toList(),
      'processingTimeMs': processingTimeMs,
      'usedFallback': usedFallback,
    };
  }

  factory NlpResult.fromJson(Map<String, dynamic> json) {
    return NlpResult(
      inputText: json['inputText'] as String,
      fraudProbability: (json['fraudProbability'] as num).toDouble(),
      confidence: (json['confidence'] as num).toDouble(),
      classification: json['classification'] as String,
      detectedFeatures: (json['detectedFeatures'] as List<dynamic>?)
          ?.map((f) => NlpFeature.fromJson(f as Map<String, dynamic>))
          .toList() ?? [],
      processingTimeMs: json['processingTimeMs'] as int? ?? 0,
      usedFallback: json['usedFallback'] as bool? ?? false,
    );
  }

  factory NlpResult.empty() {
    return NlpResult(
      inputText: '',
      fraudProbability: 0.0,
      confidence: 0.0,
      classification: 'UNKNOWN',
      detectedFeatures: [],
      processingTimeMs: 0,
      usedFallback: true,
    );
  }

  factory NlpResult.fromScore(String text, double score) {
    String classification;
    if (score <= 0.3) {
      classification = 'HAM';
    } else if (score <= 0.6) {
      classification = 'SUSPICIOUS';
    } else {
      classification = 'FRAUD';
    }

    return NlpResult(
      inputText: text,
      fraudProbability: score,
      confidence: 0.7,
      classification: classification,
      detectedFeatures: [],
      processingTimeMs: 0,
      usedFallback: false,
    );
  }
}

class NlpFeature {
  final String name;
  final String category;
  final double weight;
  final String matchedText;

  NlpFeature({
    required this.name,
    required this.category,
    required this.weight,
    this.matchedText = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'category': category,
      'weight': weight,
      'matchedText': matchedText,
    };
  }

  factory NlpFeature.fromJson(Map<String, dynamic> json) {
    return NlpFeature(
      name: json['name'] as String,
      category: json['category'] as String,
      weight: (json['weight'] as num).toDouble(),
      matchedText: json['matchedText'] as String? ?? '',
    );
  }
}

class NlpCategory {
  static const String urgency = 'URGENCY';
  static const String payment = 'PAYMENT';
  static const String threat = 'THREAT';
  static const String verification = 'VERIFICATION';
  static const String impersonation = 'IMPERSONATION';
  static const String suspicious = 'SUSPICIOUS';
}
