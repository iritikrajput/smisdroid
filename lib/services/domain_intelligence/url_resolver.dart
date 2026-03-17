import 'dart:io';

/// Extracts all URLs from a message, then resolves any
/// redirect chains to get the true final destination domain.
class UrlResolver {
  static const int _maxRedirects = 8;
  static const Duration _timeout = Duration(seconds: 6);

  // ── 1. Extract raw URLs from message text ──────────────────────
  static List<String> extractUrls(String message) {
    final regex = RegExp(
      r'(https?://[^\s"\'<>]+|www\.[a-zA-Z0-9\-]+\.[a-z]{2,}[^\s"\'<>]*)',
      caseSensitive: false,
    );
    return regex
        .allMatches(message)
        .map((m) => m.group(0)!.trim().replaceAll(RegExp(r'[.,!?;:]+$'), ''))
        .toSet()
        .toList();
  }

  // ── 2. Resolve redirect chain → return full hop list ──────────
  static Future<RedirectChainResult> resolveRedirectChain(String rawUrl) async {
    final hops = <String>[];
    String current = rawUrl.startsWith('http') ? rawUrl : 'https://$rawUrl';
    hops.add(current);

    try {
      final client = HttpClient()
        ..connectionTimeout = _timeout
        ..badCertificateCallback = (_, __, ___) => true; // allow expired certs (common in phishing)

      for (int i = 0; i < _maxRedirects; i++) {
        final request = await client.getUrl(Uri.parse(current));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader,
            'Mozilla/5.0 (Android 13; Mobile)');

        final response = await request.close();
        await response.drain(); // discard body

        final isRedirect = response.isRedirect ||
            [301, 302, 303, 307, 308].contains(response.statusCode);

        if (!isRedirect) break;

        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null || location.isEmpty) break;

        // Resolve relative redirects
        final nextUri = Uri.parse(current).resolve(location);
        current = nextUri.toString();

        if (hops.contains(current)) break; // loop detection
        hops.add(current);
      }

      client.close();
    } catch (e) {
      // Network error — return what we have so far
    }

    final finalDomain = _parseDomain(current);
    return RedirectChainResult(
      originalUrl: rawUrl,
      finalUrl: current,
      finalDomain: finalDomain ?? rawUrl,
      hops: hops,
      wasRedirected: hops.length > 1,
      hopCount: hops.length - 1,
    );
  }

  // ── 3. Parse clean domain from URL ────────────────────────────
  static String? _parseDomain(String url) {
    try {
      final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
      return uri.host.replaceAll(RegExp(r'^www\.'), '');
    } catch (_) {
      return null;
    }
  }

  // ── 4. Extract TLD from domain ────────────────────────────────
  static String extractTld(String domain) {
    final parts = domain.split('.');
    if (parts.length >= 2) {
      // Handle country-code SLDs like .co.in, .gov.in
      if (parts.length >= 3 &&
          ['co', 'gov', 'net', 'org', 'ac'].contains(parts[parts.length - 2])) {
        return '.${parts[parts.length - 2]}.${parts[parts.length - 1]}';
      }
      return '.${parts.last}';
    }
    return '.${domain}';
  }
}

class RedirectChainResult {
  final String originalUrl;
  final String finalUrl;
  final String finalDomain;
  final List<String> hops;
  final bool wasRedirected;
  final int hopCount;

  RedirectChainResult({
    required this.originalUrl,
    required this.finalUrl,
    required this.finalDomain,
    required this.hops,
    required this.wasRedirected,
    required this.hopCount,
  });

  @override
  String toString() =>
      'RedirectChain[$hopCount hops]: $originalUrl → $finalDomain';
}
