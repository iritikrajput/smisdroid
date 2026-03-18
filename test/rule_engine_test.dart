import 'package:flutter_test/flutter_test.dart';
import 'package:smisdroid/services/rule_engine.dart';

void main() {
  group('RuleEngine', () {
    test('detects urgency keywords', () {
      final result = RuleEngine.analyze('urgent pay now or face final notice');
      expect(result.score, greaterThan(0));
      expect(result.triggeredRules.any((r) => r.contains('Urgency')), true);
    });

    test('detects payment keywords', () {
      final result = RuleEngine.analyze('your bill payment of amount due rupees 500 via upi');
      expect(result.triggeredRules.any((r) => r.contains('Payment')), true);
    });

    test('detects threat keywords', () {
      final result = RuleEngine.analyze('your service will be disconnect suspended');
      expect(result.triggeredRules.any((r) => r.contains('Threat')), true);
    });

    test('detects verification keywords', () {
      final result = RuleEngine.analyze('verify your kyc update details now');
      expect(result.triggeredRules.any((r) => r.contains('Verification')), true);
    });

    test('applies combo bonus for urgency + payment + threat', () {
      final result = RuleEngine.analyze('urgent pay now or disconnect service');
      expect(result.triggeredRules.any((r) => r.contains('COMBO')), true);
      expect(result.score, greaterThan(50));
    });

    test('applies combo bonus for urgency + payment', () {
      final result = RuleEngine.analyze('urgent pay your bill immediately');
      expect(result.triggeredRules.any((r) => r.contains('COMBO')), true);
    });

    test('returns zero for safe messages', () {
      final result = RuleEngine.analyze('hello how are you doing');
      expect(result.score, equals(0));
      expect(result.triggeredRules, isEmpty);
    });

    test('score is clamped to 0-100', () {
      final result = RuleEngine.analyze(
        'urgent immediately final notice act now pay payment amount due upi '
        'disconnect suspend block deactivate terminated service stopped '
        'verify kyc update details',
      );
      expect(result.score, lessThanOrEqualTo(100));
      expect(result.score, greaterThanOrEqualTo(0));
    });
  });
}
