import 'package:flutter_test/flutter_test.dart';
import 'package:smisdroid/core/constants/risk_thresholds.dart';

void main() {
  group('RiskThresholds', () {
    test('weights sum to 1.0', () {
      final sum = RiskThresholds.nlpWeight +
          RiskThresholds.domainWeight +
          RiskThresholds.ruleWeight +
          RiskThresholds.structuralWeight;
      expect(sum, closeTo(1.0, 0.001));
    });

    group('getRiskLevel', () {
      test('returns SAFE for low scores', () {
        expect(RiskThresholds.getRiskLevel(0.0), 'SAFE');
        expect(RiskThresholds.getRiskLevel(0.1), 'SAFE');
        expect(RiskThresholds.getRiskLevel(0.3), 'SAFE');
      });

      test('returns SUSPICIOUS for mid scores', () {
        expect(RiskThresholds.getRiskLevel(0.31), 'SUSPICIOUS');
        expect(RiskThresholds.getRiskLevel(0.5), 'SUSPICIOUS');
        expect(RiskThresholds.getRiskLevel(0.6), 'SUSPICIOUS');
      });

      test('returns FRAUD for high scores', () {
        expect(RiskThresholds.getRiskLevel(0.61), 'FRAUD');
        expect(RiskThresholds.getRiskLevel(0.8), 'FRAUD');
        expect(RiskThresholds.getRiskLevel(1.0), 'FRAUD');
      });
    });

    group('normalizeDomainScore', () {
      test('normalizes 0-100 to 0-1', () {
        expect(RiskThresholds.normalizeDomainScore(0), 0.0);
        expect(RiskThresholds.normalizeDomainScore(50), 0.5);
        expect(RiskThresholds.normalizeDomainScore(100), 1.0);
      });

      test('clamps values', () {
        expect(RiskThresholds.normalizeDomainScore(150), 1.0);
        expect(RiskThresholds.normalizeDomainScore(-10), 0.0);
      });
    });

    group('normalizeRuleScore', () {
      test('normalizes 0-100 to 0-1', () {
        expect(RiskThresholds.normalizeRuleScore(0), 0.0);
        expect(RiskThresholds.normalizeRuleScore(75), 0.75);
        expect(RiskThresholds.normalizeRuleScore(100), 1.0);
      });
    });
  });
}
