import 'dart:async';
import 'package:telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/utils/logger.dart';
import '../core/constants/app_strings.dart';
import '../models/sms_analysis_result.dart';
import 'risk_engine.dart';
import 'notification_service.dart';
import 'database_service.dart';

typedef SmsCallback = void Function(SmsAnalysisResult result);

class SmsListener {
  static final SmsListener _instance = SmsListener._internal();
  factory SmsListener() => _instance;
  SmsListener._internal();

  final Telephony _telephony = Telephony.instance;
  final RiskEngine _riskEngine = RiskEngine();

  SmsCallback? _onSmsAnalyzed;
  bool _isListening = false;

  final StreamController<SmsAnalysisResult> _smsController =
      StreamController<SmsAnalysisResult>.broadcast();

  Stream<SmsAnalysisResult> get smsStream => _smsController.stream;
  bool get isListening => _isListening;

  Future<bool> requestPermissions() async {
    AppLogger.sms('Requesting SMS permissions');

    final smsStatus = await Permission.sms.request();
    final phoneStatus = await Permission.phone.request();

    if (smsStatus.isGranted && phoneStatus.isGranted) {
      AppLogger.sms('SMS permissions granted');
      return true;
    }

    AppLogger.warning('SMS permissions denied', tag: 'SMS');
    return false;
  }

  Future<bool> checkPermissions() async {
    final smsGranted = await Permission.sms.isGranted;
    final phoneGranted = await Permission.phone.isGranted;
    return smsGranted && phoneGranted;
  }

  Future<void> startListening({SmsCallback? onSmsAnalyzed}) async {
    if (_isListening) {
      AppLogger.sms('Already listening for SMS');
      return;
    }

    final hasPermission = await checkPermissions();
    if (!hasPermission) {
      final granted = await requestPermissions();
      if (!granted) {
        AppLogger.error('Cannot start SMS listener without permissions', tag: 'SMS');
        return;
      }
    }

    _onSmsAnalyzed = onSmsAnalyzed;
    _isListening = true;

    _telephony.listenIncomingSms(
      onNewMessage: _handleIncomingSms,
      onBackgroundMessage: _backgroundMessageHandler,
      listenInBackground: true,
    );

    AppLogger.sms('Started listening for incoming SMS');
  }

  void stopListening() {
    _isListening = false;
    _onSmsAnalyzed = null;
    AppLogger.sms('Stopped listening for SMS');
  }

  Future<void> _handleIncomingSms(SmsMessage message) async {
    AppLogger.sms('Received SMS from: ${message.address}');

    try {
      final result = await _riskEngine.analyzeMessage(
        message: message.body ?? '',
        sender: message.address ?? 'Unknown',
      );

      _smsController.add(result);
      _onSmsAnalyzed?.call(result);

      AppLogger.sms('SMS analyzed - Risk Level: ${result.riskLevel}');
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error analyzing SMS',
        tag: 'SMS',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<List<SmsMessage>> getInboxMessages({int count = 50}) async {
    final hasPermission = await checkPermissions();
    if (!hasPermission) {
      AppLogger.warning('No permission to read SMS inbox', tag: 'SMS');
      return [];
    }

    try {
      final messages = await _telephony.getInboxSms(
        columns: [
          SmsColumn.ADDRESS,
          SmsColumn.BODY,
          SmsColumn.DATE,
          SmsColumn.READ,
        ],
        sortOrder: [
          OrderBy(SmsColumn.DATE, sort: Sort.DESC),
        ],
      );

      return messages.take(count).toList();
    } catch (e) {
      AppLogger.error('Error fetching inbox messages', tag: 'SMS', error: e);
      return [];
    }
  }

  Future<SmsAnalysisResult> analyzeMessage({
    required String message,
    required String sender,
  }) async {
    return await _riskEngine.analyzeMessage(
      message: message,
      sender: sender,
    );
  }

  void dispose() {
    stopListening();
    _smsController.close();
  }
}

@pragma('vm:entry-point')
Future<void> _backgroundMessageHandler(SmsMessage message) async {
  AppLogger.sms('Background SMS received from: ${message.address}');

  final riskEngine = RiskEngine();
  final result = await riskEngine.analyzeMessage(
    message: message.body ?? '',
    sender: message.address ?? 'Unknown',
  );

  await NotificationService.initialize();

  if (result.riskLevel == 'FRAUD') {
    // Auto-block fraud messages
    await DatabaseService.blockMessage(result);
    AppLogger.warning('Background SMS BLOCKED as FRAUD', tag: 'SMS');

    NotificationService.showFraudAlert(
      title: AppStrings.fraudAlertTitle,
      body: 'Blocked message from: ${result.sender}',
      payload: result.originalMessage,
    );
  } else if (result.riskLevel == 'SUSPICIOUS') {
    AppLogger.warning('Background SMS flagged as SUSPICIOUS', tag: 'SMS');

    NotificationService.showSuspiciousAlert(
      title: AppStrings.suspiciousAlertTitle,
      body: 'From: ${result.sender}',
      payload: result.originalMessage,
    );
  }
}
