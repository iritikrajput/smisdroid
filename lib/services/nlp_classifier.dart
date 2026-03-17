import 'package:tflite_text_classification/tflite_text_classification.dart';

class NlpClassifier {
  bool _isLoaded = false;

  // Fallback keyword scoring when model isn't loaded
  static const Map<String, double> _fraudIndicators = {
    'disconnected': 0.85,
    'disconnect': 0.80,
    'electricity': 0.60,
    'bill': 0.55,
    'payment': 0.60,
    'verify': 0.65,
    'kyc': 0.75,
    'urgent': 0.70,
    'immediately': 0.72,
    'suspended': 0.78,
    'blocked': 0.72,
    'rupees': 0.50,
    'account': 0.45,
  };

  Future<void> initialize() async {
    // Model will be loaded from assets/models/fraud_model.tflite
    // If model file exists, tflite_text_classification handles loading
    _isLoaded = true; // Set true when actual model is embedded
  }

  Future<double> classify(String text) async {
    if (_isLoaded) {
      try {
        final result = await TfliteTextClassification().classifyText(
          params: TextClassifierParams(
            text: text,
            modelPath: 'assets/models/fraud_model.tflite',
            modelType: ModelType.mobileBert,
            delegate: 0,
          ),
        );
        // MobileBERT returns categories; extract fraud probability
        final fraudCategory = result?.classifications.firstWhere(
          (c) =>
              c.categoryName.toLowerCase().contains('fraud') ||
              c.categoryName.toLowerCase().contains('spam'),
          orElse: () => result!.classifications.last,
        );
        return fraudCategory?.score ?? _fallbackScore(text);
      } catch (_) {
        return _fallbackScore(text);
      }
    }
    return _fallbackScore(text);
  }

  // Keyword-weighted fallback scoring
  static double _fallbackScore(String text) {
    final lower = text.toLowerCase();
    double maxScore = 0.0;
    int matchCount = 0;

    for (final entry in _fraudIndicators.entries) {
      if (lower.contains(entry.key)) {
        maxScore += entry.value;
        matchCount++;
      }
    }

    if (matchCount == 0) return 0.1;
    return (maxScore / matchCount).clamp(0.0, 1.0);
  }
}
