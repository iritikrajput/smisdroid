import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/utils/extensions.dart';
import '../services/database_service.dart';
import 'alert_screen.dart';
import 'widgets/risk_badge.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _filter = 'All';
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    final riskLevel = _filter == 'All' ? null : _filter.toUpperCase();
    final logs = await DatabaseService.getLogsByRiskLevel(riskLevel);
    setState(() {
      _logs = logs;
      _isLoading = false;
    });
  }

  Future<void> _deleteLog(int id) async {
    await DatabaseService.deleteLog(id);
    _loadLogs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Detection History'),
      ),
      body: Column(
        children: [
          _buildFilterChips(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _logs.isEmpty
                    ? const Center(child: Text('No records found'))
                    : RefreshIndicator(
                        onRefresh: _loadLogs,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _logs.length,
                          itemBuilder: (context, index) =>
                              _buildLogItem(_logs[index]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: ['All', 'Fraud', 'Suspicious', 'Safe'].map((label) {
          final isSelected = _filter == label;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(label),
              selected: isSelected,
              onSelected: (_) {
                setState(() => _filter = label);
                _loadLogs();
              },
              selectedColor: _chipColor(label),
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _chipColor(String label) {
    switch (label) {
      case 'Fraud':
        return AppColors.fraud.withValues(alpha: 0.2);
      case 'Suspicious':
        return AppColors.suspicious.withValues(alpha: 0.2);
      case 'Safe':
        return AppColors.safe.withValues(alpha: 0.2);
      default:
        return AppColors.primary.withValues(alpha: 0.2);
    }
  }

  Widget _buildLogItem(Map<String, dynamic> log) {
    final riskLevel = log['risk_level'] as String;
    final sender = log['sender'] as String;
    final timestamp = DateTime.parse(log['timestamp'] as String);
    final riskScore = (log['risk_score'] as num).toDouble();
    final id = log['id'] as int;

    return Dismissible(
      key: Key('log_$id'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: AppColors.fraud,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _deleteLog(id),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AlertScreen(logData: log),
              ),
            );
          },
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: riskLevel.riskBackgroundColor,
              shape: BoxShape.circle,
            ),
            child: Icon(riskLevel.riskIcon, color: riskLevel.riskColor, size: 20),
          ),
          title: Text(sender, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(timestamp.timeAgo),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              RiskBadge(riskLevel: riskLevel),
              const SizedBox(height: 4),
              Text(
                '${(riskScore * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: riskLevel.riskColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
