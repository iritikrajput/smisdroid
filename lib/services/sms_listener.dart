import 'dart:async';
import 'package:flutter/services.dart';
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

  // Native Android EventChannel for real-time SMS
  static const _smsEventChannel = EventChannel('com.example.smisdroid/sms_events');
  StreamSubscription? _nativeSubscription;

  // Dedup: track recently analyzed messages to avoid double processing
  final Set<String> _recentlyAnalyzed = {};

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

    // Method 1: Native Android EventChannel (primary — more reliable)
    _startNativeListener();

    // Method 2: Telephony plugin (backup + background handler)
    _telephony.listenIncomingSms(
      onNewMessage: _handleIncomingSms,
      onBackgroundMessage: _backgroundMessageHandler,
      listenInBackground: true,
    );

    AppLogger.sms('Started listening for incoming SMS (native + telephony)');
  }

  void _startNativeListener() {
    _nativeSubscription?.cancel();
    _nativeSubscription = _smsEventChannel
        .receiveBroadcastStream()
        .listen(
      (event) {
        if (event is Map) {
          final sender = event['sender'] as String? ?? 'Unknown';
          final body = event['body'] as String? ?? '';
          if (body.isNotEmpty) {
            AppLogger.sms('Native SMS received from: $sender');
            _analyzeAndNotify(sender, body);
          }
        }
      },
      onError: (error) {
        AppLogger.error('Native SMS stream error: $error', tag: 'SMS');
      },
    );
  }

  void stopListening() {
    _isListening = false;
    _onSmsAnalyzed = null;
    _nativeSubscription?.cancel();
    _nativeSubscription = null;
    AppLogger.sms('Stopped listening for SMS');
  }

  /// Core analysis method — used by both native and telephony listeners.
  /// Deduplicates to avoid double processing from both listeners.
  Future<void> _analyzeAndNotify(String sender, String body) async {
    // Dedup key: sender + first 50 chars of body
    final dedupKey = '${sender}_${body.length > 50 ? body.substring(0, 50) : body}';
    if (_recentlyAnalyzed.contains(dedupKey)) {
      AppLogger.sms('Skipping duplicate SMS from: $sender');
      return;
    }
    _recentlyAnalyzed.add(dedupKey);
    // Clean old entries after 10 seconds
    Future.delayed(const Duration(seconds: 10), () {
      _recentlyAnalyzed.remove(dedupKey);
    });

    try {
      final result = await _riskEngine.analyzeMessage(
        message: body,
        sender: sender,
      );

      _smsController.add(result);
      _onSmsAnalyzed?.call(result);

      AppLogger.sms('SMS analyzed - Risk: ${result.riskLevel} (${result.riskScore.toStringAsFixed(2)}) | Type: ${result.fraudType}');
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error analyzing SMS',
        tag: 'SMS',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _handleIncomingSms(SmsMessage message) async {
    // Telephony plugin fallback — only process if native didn't catch it
    AppLogger.sms('Telephony SMS from: ${message.address}');
    await _analyzeAndNotify(
      message.address ?? 'Unknown',
      message.body ?? '',
    );
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
