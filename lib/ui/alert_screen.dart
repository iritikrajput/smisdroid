import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_strings.dart';
import '../core/utils/extensions.dart';
import '../services/database_service.dart';
import 'widgets/risk_badge.dart';

class AlertScreen extends StatelessWidget {
  final Map<String, dynamic> logData;

  const AlertScreen({super.key, required this.logData});

  @override
  Widget build(BuildContext context) {
    final riskLevel = logData['risk_level'] as String;
    final sender = logData['sender'] as String;
    final timestamp = DateTime.parse(logData['timestamp'] as String);
    final riskScore = (logData['risk_score'] as num).toDouble();
    final nlpScore = (logData['nlp_score'] as num).toDouble();
    final domainScore = logData['domain_score'] as int;
    final urls = (logData['urls'] as String?)?.split(',').where((u) => u.isNotEmpty).toList() ?? [];
    final rules = (logData['rules'] as String?)?.split('|').where((r) => r.isNotEmpty).toList() ?? [];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AppStrings.alertDetails),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) => _handleMenuAction(context, value, sender),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'trust',
                child: Row(
                  children: [
                    Icon(Icons.verified_user_outlined),
                    SizedBox(width: 8),
                    Text(AppStrings.addToTrusted),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'report',
                child: Row(
                  children: [
                    Icon(Icons.flag_outlined),
                    SizedBox(width: 8),
                    Text(AppStrings.reportFraud),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Card
            _buildHeaderCard(context, riskLevel, sender, timestamp, riskScore),
            const SizedBox(height: 16),

            // Score Breakdown
            _buildScoreBreakdown(context, nlpScore, domainScore, riskScore),
            const SizedBox(height: 16),

            // Detected URLs
            if (urls.isNotEmpty) ...[
              _buildUrlsSection(context, urls),
              const SizedBox(height: 16),
            ],

            // Triggered Rules
            if (rules.isNotEmpty) ...[
              _buildRulesSection(context, rules),
              const SizedBox(height: 16),
            ],

            // Action Buttons
            _buildActionButtons(context, sender),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(
    BuildContext context,
    String riskLevel,
    String sender,
    DateTime timestamp,
    double riskScore,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: riskLevel.riskBackgroundColor,
                shape: BoxShape.circle,
              ),
              child: Icon(
                riskLevel.riskIcon,
                color: riskLevel.riskColor,
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            RiskBadge(riskLevel: riskLevel, large: true),
            const SizedBox(height: 8),
            Text(
              '${(riskScore * 100).toStringAsFixed(1)}% Risk',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: riskLevel.riskColor,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildInfoItem(
                    context,
                    Icons.person_outline,
                    AppStrings.sender,
                    sender,
                  ),
                ),
                Expanded(
                  child: _buildInfoItem(
                    context,
                    Icons.access_time,
                    AppStrings.timestamp,
                    timestamp.formatted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Column(
      children: [
        Icon(icon, color: AppColors.textSecondary, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildScoreBreakdown(
    BuildContext context,
    double nlpScore,
    int domainScore,
    double riskScore,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.analysisBreakdown,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _buildScoreBar(
              context,
              AppStrings.nlpScore,
              'AI-based text analysis',
              nlpScore,
              AppColors.primary,
            ),
            const SizedBox(height: 12),
            _buildScoreBar(
              context,
              AppStrings.domainScore,
              'URL and domain analysis',
              domainScore / 100,
              AppColors.warning,
            ),
            const SizedBox(height: 12),
            _buildScoreBar(
              context,
              'Combined ${AppStrings.riskScore}',
              'Weighted final score',
              riskScore,
              _getScoreColor(riskScore),
            ),
          ],
        ),
      ),
    );
  }

  Color _getScoreColor(double score) {
    if (score <= 0.3) return AppColors.safe;
    if (score <= 0.6) return AppColors.suspicious;
    return AppColors.fraud;
  }

  Widget _buildScoreBar(
    BuildContext context,
    String title,
    String subtitle,
    double value,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            Text(
              '${(value * 100).toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            backgroundColor: color.withOpacity(0.2),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildUrlsSection(BuildContext context, List<String> urls) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.link, color: AppColors.warning),
                const SizedBox(width: 8),
                Text(
                  AppStrings.detectedUrls,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...urls.map((url) => _buildUrlItem(context, url)),
          ],
        ),
      ),
    );
  }

  Widget _buildUrlItem(BuildContext context, String url) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.fraudLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.fraud.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: AppColors.fraud, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              url,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('URL copied to clipboard')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRulesSection(BuildContext context, List<String> rules) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.rule, color: AppColors.suspicious),
                const SizedBox(width: 8),
                Text(
                  AppStrings.triggeredRules,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: rules.map((rule) => _buildRuleChip(context, rule)).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRuleChip(BuildContext context, String rule) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.suspiciousLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.suspicious.withOpacity(0.3)),
      ),
      child: Text(
        rule,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.suspicious,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, String sender) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _addToTrusted(context, sender),
            icon: const Icon(Icons.verified_user_outlined),
            label: const Text(AppStrings.markAsSafe),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              // Report fraud functionality
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Reported as fraud')),
              );
            },
            icon: const Icon(Icons.flag_outlined),
            label: const Text(AppStrings.reportFraud),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.fraud,
            ),
          ),
        ),
      ],
    );
  }

  void _handleMenuAction(BuildContext context, String action, String sender) {
    switch (action) {
      case 'trust':
        _addToTrusted(context, sender);
        break;
      case 'report':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reported as fraud')),
        );
        break;
    }
  }

  Future<void> _addToTrusted(BuildContext context, String sender) async {
    await DatabaseService.addTrustedSender(sender);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$sender added to trusted senders')),
      );
    }
  }
}
