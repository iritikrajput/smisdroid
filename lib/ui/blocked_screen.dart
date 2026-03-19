import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/utils/extensions.dart';
import '../services/database_service.dart';

class BlockedScreen extends StatefulWidget {
  const BlockedScreen({super.key});

  @override
  State<BlockedScreen> createState() => _BlockedScreenState();
}

class _BlockedScreenState extends State<BlockedScreen> {
  List<Map<String, dynamic>> _blockedMessages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBlocked();
  }

  Future<void> _loadBlocked() async {
    setState(() => _isLoading = true);
    final messages = await DatabaseService.getBlockedMessages();
    setState(() {
      _blockedMessages = messages;
      _isLoading = false;
    });
  }

  Future<void> _unblockMessage(int id) async {
    await DatabaseService.unblockMessage(id);
    _loadBlocked();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message unblocked')),
      );
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Blocked'),
        content: const Text('Remove all blocked messages? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear All', style: TextStyle(color: AppColors.fraud)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DatabaseService.clearBlocked();
      _loadBlocked();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Blocked Messages'),
        actions: [
          if (_blockedMessages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _clearAll,
              tooltip: 'Clear all',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _blockedMessages.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadBlocked,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _blockedMessages.length,
                    itemBuilder: (context, index) =>
                        _buildBlockedItem(_blockedMessages[index]),
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.block,
            size: 64,
            color: AppColors.textHint,
          ),
          const SizedBox(height: 16),
          Text(
            'No blocked messages',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Fraudulent messages will be automatically\nblocked and shown here.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildBlockedItem(Map<String, dynamic> blocked) {
    final sender = blocked['sender'] as String;
    final message = blocked['message'] as String;
    final riskScore = (blocked['risk_score'] as num).toDouble();
    final blockedAt = DateTime.parse(blocked['blocked_at'] as String);
    final id = blocked['id'] as int;
    final urls = (blocked['urls'] as String?)
            ?.split(',')
            .where((u) => u.isNotEmpty)
            .toList() ??
        [];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with red blocked indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.fraudLight,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.block, color: AppColors.fraud, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sender,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: AppColors.fraud,
                              fontWeight: FontWeight.bold,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        blockedAt.timeAgo,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.fraud,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${(riskScore * 100).toStringAsFixed(0)}% Risk',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Message content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                if (urls.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...urls.map((url) => Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.fraudLight,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: AppColors.fraud.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.link_off,
                                color: AppColors.fraud, size: 14),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                url,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.fraud,
                                  fontFamily: 'monospace',
                                  decoration: TextDecoration.lineThrough,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ],
            ),
          ),

          // Actions
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _showMessageDetail(context, blocked),
                  icon: const Icon(Icons.info_outline, size: 18),
                  label: const Text('Details'),
                ),
                TextButton.icon(
                  onPressed: () => _unblockMessage(id),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Unblock'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.safe),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMessageDetail(BuildContext context, Map<String, dynamic> blocked) {
    final message = blocked['message'] as String;
    final sender = blocked['sender'] as String;
    final riskScore = (blocked['risk_score'] as num).toDouble();
    final nlpScore = (blocked['nlp_score'] as num).toDouble();
    final domainScore = blocked['domain_score'] as int;
    final rules = (blocked['rules'] as String?)
            ?.split('|')
            .where((r) => r.isNotEmpty)
            .toList() ??
        [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textHint,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Blocked Message Details',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              _detailRow('Sender', sender),
              _detailRow('Risk Score', '${(riskScore * 100).toStringAsFixed(1)}%'),
              _detailRow('NLP Score', '${(nlpScore * 100).toStringAsFixed(1)}%'),
              _detailRow('Domain Score', '$domainScore/100'),
              const SizedBox(height: 12),
              Text('Full Message',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(message),
              ),
              if (rules.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Triggered Rules',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: rules
                      .map((rule) => Chip(
                            label: Text(rule, style: const TextStyle(fontSize: 11)),
                            backgroundColor: AppColors.fraudLight,
                            side: BorderSide(
                                color: AppColors.fraud.withValues(alpha: 0.3)),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
