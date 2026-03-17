import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_strings.dart';
import '../core/utils/extensions.dart';
import '../services/database_service.dart';
import '../services/sms_listener.dart';
import '../models/sms_analysis_result.dart';
import 'alert_screen.dart';
import 'widgets/stat_card.dart';
import 'widgets/risk_badge.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final SmsListener _smsListener = SmsListener();
  Map<String, int> _stats = {'total': 0, 'fraud': 0, 'suspicious': 0, 'safe': 0};
  List<Map<String, dynamic>> _recentLogs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _listenToSms();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final stats = await DatabaseService.getStats();
      final logs = await DatabaseService.getRecentLogs(limit: 10);

      setState(() {
        _stats = stats;
        _recentLogs = logs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _listenToSms() {
    _smsListener.smsStream.listen((result) {
      _loadData(); // Refresh data when new SMS is analyzed
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AppStrings.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatsSection(),
                    const SizedBox(height: 24),
                    _buildChartSection(),
                    const SizedBox(height: 24),
                    _buildRecentAlertsSection(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStatsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Overview',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatCard(
                title: AppStrings.totalScanned,
                value: _stats['total'].toString(),
                icon: Icons.sms_outlined,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                title: AppStrings.fraudDetected,
                value: _stats['fraud'].toString(),
                icon: Icons.dangerous_outlined,
                color: AppColors.fraud,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatCard(
                title: AppStrings.suspicious,
                value: _stats['suspicious'].toString(),
                icon: Icons.warning_amber_outlined,
                color: AppColors.suspicious,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                title: AppStrings.safe,
                value: _stats['safe'].toString(),
                icon: Icons.check_circle_outline,
                color: AppColors.safe,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChartSection() {
    final total = _stats['total'] ?? 0;
    if (total == 0) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Detection Summary',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 40,
                        sections: [
                          PieChartSectionData(
                            color: AppColors.chartSafe,
                            value: (_stats['safe'] ?? 0).toDouble(),
                            title: '${((_stats['safe'] ?? 0) / total * 100).toStringAsFixed(0)}%',
                            radius: 50,
                            titleStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          PieChartSectionData(
                            color: AppColors.chartSuspicious,
                            value: (_stats['suspicious'] ?? 0).toDouble(),
                            title: '${((_stats['suspicious'] ?? 0) / total * 100).toStringAsFixed(0)}%',
                            radius: 50,
                            titleStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          PieChartSectionData(
                            color: AppColors.chartFraud,
                            value: (_stats['fraud'] ?? 0).toDouble(),
                            title: '${((_stats['fraud'] ?? 0) / total * 100).toStringAsFixed(0)}%',
                            radius: 50,
                            titleStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLegendItem('Safe', AppColors.chartSafe, _stats['safe'] ?? 0),
                        const SizedBox(height: 8),
                        _buildLegendItem('Suspicious', AppColors.chartSuspicious, _stats['suspicious'] ?? 0),
                        const SizedBox(height: 8),
                        _buildLegendItem('Fraud', AppColors.chartFraud, _stats['fraud'] ?? 0),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, int count) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$label ($count)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _buildRecentAlertsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              AppStrings.recentAlerts,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (_recentLogs.isNotEmpty)
              TextButton(
                onPressed: () {
                  // Navigate to full history
                },
                child: const Text(AppStrings.viewAll),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_recentLogs.isEmpty)
          _buildEmptyState()
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _recentLogs.length,
            itemBuilder: (context, index) {
              final log = _recentLogs[index];
              return _buildAlertCard(log);
            },
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 16),
            Text(
              AppStrings.noAlertsYet,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.startMonitoring,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> log) {
    final riskLevel = log['risk_level'] as String;
    final sender = log['sender'] as String;
    final timestamp = DateTime.parse(log['timestamp'] as String);
    final riskScore = (log['risk_score'] as num).toDouble();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AlertScreen(logData: log),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: riskLevel.riskBackgroundColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  riskLevel.riskIcon,
                  color: riskLevel.riskColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sender,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      timestamp.timeAgo,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  RiskBadge(riskLevel: riskLevel),
                  const SizedBox(height: 4),
                  Text(
                    '${(riskScore * 100).toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: riskLevel.riskColor,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
