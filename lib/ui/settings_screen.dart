import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_strings.dart';
import '../services/database_service.dart';
import '../services/sms_listener.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<String> _trustedSenders = [];
  bool _isScanning = false;
  int _scannedCount = 0;
  int _scanTotal = 0;

  @override
  void initState() {
    super.initState();
    _loadTrustedSenders();
  }

  Future<void> _loadTrustedSenders() async {
    final senders = await DatabaseService.getTrustedSenders();
    setState(() => _trustedSenders = senders);
  }

  Future<void> _removeTrustedSender(String sender) async {
    await DatabaseService.removeTrustedSender(sender);
    _loadTrustedSenders();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed $sender from trusted senders')),
      );
    }
  }

  Future<void> _scanInbox() async {
    setState(() {
      _isScanning = true;
      _scannedCount = 0;
    });

    final smsListener = SmsListener();
    final messages = await smsListener.getInboxMessages(count: 50);
    setState(() => _scanTotal = messages.length);

    for (final message in messages) {
      final body = message.body;
      final address = message.address;
      if (body != null && address != null) {
        await smsListener.analyzeMessage(message: body, sender: address);
        setState(() => _scannedCount++);
      }
    }

    setState(() => _isScanning = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scanned $_scannedCount messages')),
      );
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.clearHistory),
        content: const Text('This will delete all detection logs. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.confirm, style: TextStyle(color: AppColors.fraud)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DatabaseService.clearHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('History cleared')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AppStrings.settings),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Scan Inbox
          _buildSectionTitle('Inbox Scanner'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Analyze existing SMS messages in your inbox for potential fraud.',
                  ),
                  const SizedBox(height: 12),
                  if (_isScanning) ...[
                    LinearProgressIndicator(
                      value: _scanTotal > 0 ? _scannedCount / _scanTotal : null,
                    ),
                    const SizedBox(height: 8),
                    Text('Scanning $_scannedCount / $_scanTotal messages...'),
                  ] else
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _scanInbox,
                        icon: const Icon(Icons.search),
                        label: const Text('Scan Inbox'),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Trusted Senders
          _buildSectionTitle(AppStrings.trustedSenders),
          Card(
            child: _trustedSenders.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No trusted senders yet. Mark senders as safe from the alert details screen.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _trustedSenders.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final sender = _trustedSenders[index];
                      return ListTile(
                        leading: const Icon(Icons.verified_user, color: AppColors.safe),
                        title: Text(sender),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: AppColors.fraud),
                          onPressed: () => _removeTrustedSender(sender),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 24),

          // Data Management
          _buildSectionTitle('Data Management'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text(AppStrings.clearHistory),
                  subtitle: const Text('Remove all detection logs'),
                  onTap: _clearHistory,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cached),
                  title: const Text('Clear Domain Cache'),
                  subtitle: const Text('Remove cached domain analysis results'),
                  onTap: () async {
                    await DatabaseService.clearCache();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Domain cache cleared')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // About
          _buildSectionTitle(AppStrings.about),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.appName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppStrings.appTagline,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Version ${AppStrings.appVersion}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Edge AI-powered SMS fraud detection.\n'
                    '100% on-device processing. Zero cloud dependency.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
    );
  }
}
