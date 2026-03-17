import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../core/utils/logger.dart';

class NlpClassifier {
  Interpreter? _interpreter;
  Map<String, int>? _vocabulary;
  bool _isLoaded = false;

  static const int _maxSeqLength = 128;

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
    'otp': 0.65,
    'click': 0.55,
    'link': 0.50,
    'expired': 0.70,
    'deactivated': 0.75,
    'upi': 0.55,
    'bank': 0.50,
    'update': 0.45,
    'pan': 0.60,
    'aadhar': 0.65,
    'aadhaar': 0.65,
    'reward': 0.55,
    'won': 0.60,
    'prize': 0.65,
    'lottery': 0.75,
    'congratulations': 0.60,
  };

  Future<void> initialize() async {
    try {
      // Load vocabulary
      final vocabJson = await rootBundle.loadString('assets/nlp/vocabulary.json');
      _vocabulary = Map<String, int>.from(json.decode(vocabJson));

      // Load TFLite model
      _interpreter = await Interpreter.fromAsset('assets/models/fraud_model.tflite');
      _isLoaded = true;
      AppLogger.nlp('NLP classifier initialized successfully');
    } catch (e) {
      AppLogger.warning('Failed to load NLP model, using fallback: $e', tag: 'NLP');
      _isLoaded = false;
    }
  }

  Future<double> classify(String text) async {
    if (!_isLoaded || _interpreter == null) {
      return _fallbackScore(text);
    }

    try {
      // Tokenize text
      final tokens = _tokenize(text);

      // Prepare input tensor
      final input = List.filled(_maxSeqLength, 0);
      for (var i = 0; i < tokens.length && i < _maxSeqLength; i++) {
        input[i] = tokens[i];
      }

      // Prepare output tensor
      final output = List.filled(1, 0.0).reshape([1, 1]);

      // Run inference
      _interpreter!.run([input], output);

      final score = output[0][0] as double;
      AppLogger.nlp('NLP model score: $score');
      return score.clamp(0.0, 1.0);
    } catch (e) {
      AppLogger.error('NLP inference failed: $e', tag: 'NLP');
      return _fallbackScore(text);
    }
  }

  List<int> _tokenize(String text) {
    if (_vocabulary == null) return [];

    final words = text.toLowerCase().split(RegExp(r'\s+'));
    final tokens = <int>[];

    for (final word in words) {
      final cleanWord = word.replaceAll(RegExp(r'[^\w]'), '');
      if (cleanWord.isNotEmpty && _vocabulary!.containsKey(cleanWord)) {
        tokens.add(_vocabulary![cleanWord]!);
      }
    }

    return tokens;
  }

  // Keyword-weighted fallback scoring
  double _fallbackScore(String text) {
    final lower = text.toLowerCase();
    double totalScore = 0.0;
    int matchCount = 0;

    for (final entry in _fraudIndicators.entries) {
      if (lower.contains(entry.key)) {
        totalScore += entry.value;
        matchCount++;
      }
    }

    if (matchCount == 0) return 0.1;

    // Average score with boost for multiple matches
    final avgScore = totalScore / matchCount;
    final matchBoost = (matchCount - 1) * 0.05;

    return (avgScore + matchBoost).clamp(0.0, 1.0);
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isLoaded = false;
  }
}
