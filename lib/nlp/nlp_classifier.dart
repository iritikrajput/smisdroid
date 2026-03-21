import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../core/utils/logger.dart';

class NlpClassifier {
  Interpreter? _interpreter;
  Map<String, int>? _vocabulary;
  bool _isLoaded = false;

  static const int _maxSeqLength = 128;
  static const int _clsTokenId = 101;
  static const int _sepTokenId = 102;
  static const int _unkTokenId = 100;
  static const int _padTokenId = 0;

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
      AppLogger.nlp('NLP classifier initialized — vocab: ${_vocabulary!.length} tokens');
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
      // WordPiece tokenize with [CLS] and [SEP]
      final tokenIds = _wordPieceTokenize(text);

      // Prepare input tensor [1, 128]
      final input = List.filled(_maxSeqLength, _padTokenId);
      for (var i = 0; i < tokenIds.length && i < _maxSeqLength; i++) {
        input[i] = tokenIds[i];
      }

      // Prepare output tensor [1, 1]
      final output = List.filled(1, 0.0).reshape([1, 1]);

      // Run inference
      _interpreter!.run([input], output);

      final score = (output[0][0] as double).clamp(0.0, 1.0);
      AppLogger.nlp('NLP model score: $score');
      return score;
    } catch (e) {
      AppLogger.error('NLP inference failed: $e', tag: 'NLP');
      return _fallbackScore(text);
    }
  }

  /// WordPiece tokenization matching HuggingFace MobileBERT tokenizer.
  /// Produces: [CLS] token1 token2 ... [SEP]
  List<int> _wordPieceTokenize(String text) {
    if (_vocabulary == null) return [_clsTokenId, _sepTokenId];

    final tokens = <int>[_clsTokenId];

    // Step 1: BasicTokenizer — lowercase, split on whitespace, then split
    // each punctuation character as its own token (matching HuggingFace)
    final basicTokens = _basicTokenize(text.toLowerCase());

    for (final word in basicTokens) {
      if (word.isEmpty) continue;
      if (tokens.length >= _maxSeqLength - 1) break;

      // Step 2: WordPiece — try full word, then break into subwords
      if (_vocabulary!.containsKey(word)) {
        tokens.add(_vocabulary![word]!);
        continue;
      }

      // WordPiece subword splitting
      var remaining = word;
      var isFirst = true;

      while (remaining.isNotEmpty && tokens.length < _maxSeqLength - 1) {
        String? bestMatch;
        int bestLen = 0;

        for (var end = remaining.length; end > 0; end--) {
          final substr = isFirst
              ? remaining.substring(0, end)
              : '##${remaining.substring(0, end)}';

          if (_vocabulary!.containsKey(substr)) {
            bestMatch = substr;
            bestLen = end;
            break;
          }
        }

        if (bestMatch != null) {
          tokens.add(_vocabulary![bestMatch]!);
          remaining = remaining.substring(bestLen);
          isFirst = false;
        } else {
          tokens.add(_unkTokenId);
          break;
        }
      }
    }

    if (tokens.length < _maxSeqLength) {
      tokens.add(_sepTokenId);
    }

    return tokens;
  }

  /// BasicTokenizer: split text into tokens, treating each punctuation
  /// character as a separate token (matching HuggingFace behavior).
  /// "http://xyz.tk" → ["http", ":", "/", "/", "xyz", ".", "tk"]
  List<String> _basicTokenize(String text) {
    final result = <String>[];
    final buffer = StringBuffer();

    for (final char in text.runes) {
      final c = String.fromCharCode(char);

      if (_isPunctuation(char) || _isChinese(char)) {
        // Flush buffer as a word token
        if (buffer.isNotEmpty) {
          result.add(buffer.toString());
          buffer.clear();
        }
        // Add punctuation as its own token
        result.add(c);
      } else if (c.trim().isEmpty) {
        // Whitespace — flush buffer
        if (buffer.isNotEmpty) {
          result.add(buffer.toString());
          buffer.clear();
        }
      } else {
        buffer.write(c);
      }
    }

    if (buffer.isNotEmpty) {
      result.add(buffer.toString());
    }

    return result;
  }

  /// Check if a character is punctuation (matching BERT's definition)
  bool _isPunctuation(int cp) {
    if ((cp >= 33 && cp <= 47) ||   // ! " # $ % & ' ( ) * + , - . /
        (cp >= 58 && cp <= 64) ||   // : ; < = > ? @
        (cp >= 91 && cp <= 96) ||   // [ \ ] ^ _ `
        (cp >= 123 && cp <= 126)) { // { | } ~
      return true;
    }
    return false;
  }

  bool _isChinese(int cp) {
    return (cp >= 0x4E00 && cp <= 0x9FFF);
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
