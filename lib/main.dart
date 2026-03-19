import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_strings.dart';
import 'ui/dashboard_screen.dart';
import 'services/sms_listener.dart';
import 'services/notification_service.dart';
import 'services/database_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize notification service
  await NotificationService.initialize();

  runApp(const SMISDroidApp());
}

class SMISDroidApp extends StatefulWidget {
  const SMISDroidApp({super.key});

  @override
  State<SMISDroidApp> createState() => _SMISDroidAppState();
}

class _SMISDroidAppState extends State<SMISDroidApp> {
  final SmsListener _smsListener = SmsListener();

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    // Start SMS listening
    await _smsListener.startListening(
      onSmsAnalyzed: (result) {
        if (result.riskLevel == 'FRAUD') {
          // Auto-block fraud messages
          DatabaseService.blockMessage(result);
          NotificationService.showFraudAlert(
            title: AppStrings.fraudAlertTitle,
            body: 'Blocked message from: ${result.sender}',
            payload: result.originalMessage,
          );
        } else if (result.riskLevel == 'SUSPICIOUS') {
          NotificationService.showSuspiciousAlert(
            title: AppStrings.suspiciousAlertTitle,
            body: 'From: ${result.sender}',
            payload: result.originalMessage,
          );
        }
      },
    );
  }

  @override
  void dispose() {
    _smsListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const DashboardScreen(),
    );
  }
}
