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
}
