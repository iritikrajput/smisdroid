import '../core/constants/risk_thresholds.dart';
import '../core/utils/logger.dart';
import '../models/sms_analysis_result.dart';
import '../nlp/nlp_classifier.dart';
import 'preprocessor.dart';
import 'rule_engine.dart';
import 'domain_intelligence/domain_intelligence.dart';
import 'database_service.dart';

class RiskEngine {
  final NlpClassifier _nlpClassifier = NlpClassifier();

  Future<SmsAnalysisResult> analyzeMessage({
    required String message,
    required String sender,
  }) async {
    AppLogger.risk('Starting analysis for message from: $sender');
    final startTime = DateTime.now();

    // Check if sender is trusted
    final isTrusted = await DatabaseService.isTrustedSender(sender);
    if (isTrusted) {
      AppLogger.risk('Sender is trusted, marking as SAFE');
      return SmsAnalysisResult(
        originalMessage: message,
        sender: sender,
        riskLevel: 'SAFE',
        riskScore: 0.0,
        detectedUrls: [],
        triggeredRules: ['Trusted Sender'],
        domainScore: 0,
        nlpScore: 0.0,
        timestamp: DateTime.now(),
        explanation: {'reason': 'Trusted sender'},
      );
    }

    // Preprocess message
    final cleanedText = MessagePreprocessor.cleanText(message);
    final urls = MessagePreprocessor.extractUrls(message);
    AppLogger.risk('Extracted ${urls.length} URLs from message');

    // Run parallel analysis
    final results = await Future.wait([
      _runNlpAnalysis(cleanedText),
      Future.value(_runRuleAnalysis(cleanedText)),
      _runDomainAnalysis(message, urls),
    ]);

    final nlpScore = results[0] as double;
    final ruleResult = results[1] as RuleAnalysisResult;
    final domainResult = results[2] as Map<String, dynamic>;

    final ruleScore = ruleResult.score;
    final triggeredRules = ruleResult.triggeredRules;
    final domainScore = domainResult['score'] as int;
    final domainIndicators = domainResult['indicators'] as List<String>;

    // Calculate final risk score using weighted formula
    final normalizedDomain = RiskThresholds.normalizeDomainScore(domainScore);
    final normalizedRule = RiskThresholds.normalizeRuleScore(ruleScore);

    final finalScore = (RiskThresholds.nlpWeight * nlpScore) +
        (RiskThresholds.domainWeight * normalizedDomain) +
        (RiskThresholds.ruleWeight * normalizedRule);

    final riskLevel = RiskThresholds.getRiskLevel(finalScore);

    final endTime = DateTime.now();
    final analysisTime = endTime.difference(startTime).inMilliseconds;
    AppLogger.risk('Analysis completed in ${analysisTime}ms - Risk: $riskLevel ($finalScore)');

    // Create result
    final result = SmsAnalysisResult(
      originalMessage: message,
      sender: sender,
      riskLevel: riskLevel,
      riskScore: finalScore,
      detectedUrls: urls,
      triggeredRules: [...triggeredRules, ...domainIndicators],
      domainScore: domainScore,
      nlpScore: nlpScore,
      timestamp: DateTime.now(),
      explanation: {
        'nlp_score': nlpScore,
        'nlp_contribution': nlpScore * RiskThresholds.nlpWeight,
        'domain_score': domainScore,
        'domain_contribution': normalizedDomain * RiskThresholds.domainWeight,
        'rule_score': ruleScore,
        'rule_contribution': normalizedRule * RiskThresholds.ruleWeight,
        'final_score': finalScore,
        'analysis_time_ms': analysisTime,
      },
    );

    // Log to database
    await DatabaseService.logResult(result);

    return result;
  }

  Future<double> _runNlpAnalysis(String text) async {
    try {
      final score = await _nlpClassifier.classify(text);
      AppLogger.nlp('NLP score: $score');
      return score;
    } catch (e) {
      AppLogger.error('NLP analysis failed', tag: 'NLP', error: e);
      return 0.0;
    }
  }

  RuleAnalysisResult _runRuleAnalysis(String text) {
    try {
      final result = RuleEngine.analyze(text);
      AppLogger.rule('Rule score: ${result.score}, Rules: ${result.triggeredRules}');
      return result;
    } catch (e) {
      AppLogger.error('Rule analysis failed', tag: 'Rule', error: e);
      return RuleAnalysisResult(score: 0, triggeredRules: []);
    }
  }

  Future<Map<String, dynamic>> _runDomainAnalysis(
    String message,
    List<String> urls,
  ) async {
    if (urls.isEmpty) {
      AppLogger.domain('No URLs to analyze');
      return {'score': 0, 'indicators': <String>[]};
    }

    try {
      // Check cache first
      for (final url in urls) {
        final domain = MessagePreprocessor.extractDomain(url);
        if (domain != null) {
          final cached = await DatabaseService.getCachedDomain(domain);
          if (cached != null) {
            AppLogger.domain('Using cached result for $domain');
            return {
              'score': cached['score'] as int,
              'indicators': ['Cached: ${cached['is_phishing'] == 1 ? 'Known phishing' : 'Previously analyzed'}'],
            };
          }
        }
      }

      // Run full domain analysis
      final report = await DomainIntelligence.analyze(message);

      final indicators = <String>[];
      if (report.results.isNotEmpty) {
        final topResult = report.results.first;
        for (final indicator in topResult.indicators) {
          indicators.add('${indicator.category}: ${indicator.description}');
        }

        // Cache the result
        final domain = topResult.domain;
        if (domain.isNotEmpty) {
          await DatabaseService.cacheDomain(
            domain: domain,
            isPhishing: report.highestScore > 50,
            score: report.highestScore,
          );
        }
      }

      AppLogger.domain('Domain score: ${report.highestScore}');
      return {
        'score': report.highestScore,
        'indicators': indicators,
      };
    } catch (e) {
      AppLogger.error('Domain analysis failed', tag: 'Domain', error: e);
      return {'score': 0, 'indicators': <String>[]};
    }
  }

  // Quick analysis without domain intelligence (for offline mode)
  SmsAnalysisResult analyzeOffline({
    required String message,
    required String sender,
  }) {
    AppLogger.risk('Running offline analysis');

    final cleanedText = MessagePreprocessor.cleanText(message);
    final urls = MessagePreprocessor.extractUrls(message);

    // Synchronous analysis
    final ruleResult = RuleEngine.analyze(cleanedText);
    final ruleScore = ruleResult.score;
    final triggeredRules = ruleResult.triggeredRules;

    // Simple URL presence penalty for offline mode
    final urlPenalty = urls.isNotEmpty ? 0.2 : 0.0;
    final normalizedRule = RiskThresholds.normalizeRuleScore(ruleScore);

    final finalScore = (normalizedRule * 0.7) + urlPenalty;
    final riskLevel = RiskThresholds.getRiskLevel(finalScore);

    return SmsAnalysisResult(
      originalMessage: message,
      sender: sender,
      riskLevel: riskLevel,
      riskScore: finalScore,
      detectedUrls: urls,
      triggeredRules: triggeredRules,
      domainScore: 0,
      nlpScore: 0.0,
      timestamp: DateTime.now(),
      explanation: {
        'mode': 'offline',
        'rule_score': ruleScore,
        'url_penalty': urlPenalty,
      },
    );
  }
}
