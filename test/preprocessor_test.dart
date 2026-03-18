import 'package:flutter_test/flutter_test.dart';
import 'package:smisdroid/services/preprocessor.dart';

void main() {
  group('MessagePreprocessor', () {
    group('cleanText', () {
      test('converts to lowercase', () {
        expect(MessagePreprocessor.cleanText('HELLO WORLD'), 'hello world');
      });

      test('normalizes whitespace', () {
        expect(MessagePreprocessor.cleanText('hello   world'), 'hello world');
      });

      test('trims text', () {
        expect(MessagePreprocessor.cleanText('  hello  '), 'hello');
      });
    });

    group('extractUrls', () {
      test('extracts http URLs', () {
        final urls = MessagePreprocessor.extractUrls('Visit http://example.com now');
        expect(urls, contains('http://example.com'));
      });

      test('extracts https URLs', () {
        final urls = MessagePreprocessor.extractUrls('Visit https://secure.example.com/path');
        expect(urls.length, 1);
        expect(urls.first, contains('https://secure.example.com'));
      });

      test('extracts multiple URLs', () {
        final urls = MessagePreprocessor.extractUrls(
          'Click http://a.com or http://b.com',
        );
        expect(urls.length, 2);
      });

      test('returns empty for no URLs', () {
        final urls = MessagePreprocessor.extractUrls('No links here');
        expect(urls, isEmpty);
      });
    });

    group('extractDomain', () {
      test('extracts domain from full URL', () {
        expect(MessagePreprocessor.extractDomain('https://example.com/path'), 'example.com');
      });

      test('extracts domain from URL', () {
        final domain = MessagePreprocessor.extractDomain('https://example.com/path');
        expect(domain, 'example.com');
      });
    });

    group('tokenize', () {
      test('splits text into tokens', () {
        final tokens = MessagePreprocessor.tokenize('Hello world!');
        expect(tokens, contains('hello'));
        expect(tokens, contains('world'));
      });

      test('filters short tokens', () {
        final tokens = MessagePreprocessor.tokenize('I am a developer');
        expect(tokens, isNot(contains('am')));
        expect(tokens, contains('developer'));
      });
    });

    group('calculateStructuralScore', () {
      test('returns 0 for safe message', () {
        final score = MessagePreprocessor.calculateStructuralScore(
          'Hello, how are you doing today?',
          [],
        );
        expect(score, lessThan(0.3));
      });

      test('increases score for URL presence', () {
        final score = MessagePreprocessor.calculateStructuralScore(
          'Click here http://example.com',
          ['http://example.com'],
        );
        expect(score, greaterThanOrEqualTo(0.3));
      });

      test('increases score for currency symbols', () {
        final score = MessagePreprocessor.calculateStructuralScore(
          'Pay Rs. 500 immediately',
          [],
        );
        expect(score, greaterThan(0.0));
      });

      test('score is clamped to 0-1', () {
        final score = MessagePreprocessor.calculateStructuralScore(
          'URGENT!!! Pay Rs.500 NOW!! http://x.com',
          ['http://x.com'],
        );
        expect(score, lessThanOrEqualTo(1.0));
        expect(score, greaterThanOrEqualTo(0.0));
      });
    });
  });
}
