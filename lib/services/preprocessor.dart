class MessagePreprocessor {
  static final RegExp _urlRegex = RegExp(
    r'(https?:\/\/[^\s]+|www\.[^\s]+|[a-zA-Z0-9\-]+\.[a-z]{2,}\/[^\s]*)',
    caseSensitive: false,
  );

  static final RegExp _domainRegex = RegExp(
    r'(?:https?:\/\/)?(?:www\.)?([a-zA-Z0-9\-]+\.[a-z]{2,}(?:\.[a-z]{2})?)',
    caseSensitive: false,
  );

  static String cleanText(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static List<String> extractUrls(String text) {
    return _urlRegex
        .allMatches(text)
        .map((m) => m.group(0)!)
        .toList();
  }

  static String? extractDomain(String url) {
    final match = _domainRegex.firstMatch(url);
    return match?.group(1);
  }

  static List<String> tokenize(String text) {
    return cleanText(text)
        .split(RegExp(r'[\s.,!?;:]+'))
        .where((t) => t.length > 2)
        .toList();
  }

  static Map<String, dynamic> extractFeatures(String text) {
    final urls = extractUrls(text);
    final tokens = tokenize(text);
    return {
      'clean_text': cleanText(text),
      'urls': urls,
      'tokens': tokens,
      'has_url': urls.isNotEmpty,
      'url_count': urls.length,
      'message_length': text.length,
      'digit_count': RegExp(r'\d').allMatches(text).length,
      'uppercase_ratio': text.split('').where((c) => c == c.toUpperCase() && c != c.toLowerCase()).length / text.length,
    };
  }

  /// Calculate structural features score (0.0 - 1.0)
  static double calculateStructuralScore(String text, List<String> urls) {
    double score = 0.0;

    // Has URL
    if (urls.isNotEmpty) score += 0.3;

    // High uppercase ratio (>30%)
    final letters = text.split('').where((c) => c != c.toUpperCase() || c != c.toLowerCase());
    if (letters.isNotEmpty) {
      final upper = text.split('').where((c) => c == c.toUpperCase() && c != c.toLowerCase()).length;
      if (upper / text.length > 0.3) score += 0.2;
    }

    // Contains currency symbols
    if (RegExp(r'(₹|Rs\.?|INR|rupee)', caseSensitive: false).hasMatch(text)) {
      score += 0.15;
    }

    // Short message with URL (likely phishing)
    if (urls.isNotEmpty && text.length < 100) score += 0.2;

    // Multiple exclamation marks
    if (RegExp(r'!{2,}').hasMatch(text)) score += 0.15;

    return score.clamp(0.0, 1.0);
  }
}
