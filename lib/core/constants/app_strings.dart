class AppStrings {
  AppStrings._();

  // App Info
  static const String appName = 'SMISDroid';
  static const String appTagline = 'Real-Time SMS Fraud Detection';
  static const String appVersion = '1.0.0';

  // Dashboard
  static const String dashboard = 'Dashboard';
  static const String totalScanned = 'Total Scanned';
  static const String fraudDetected = 'Fraud Detected';
  static const String suspicious = 'Suspicious';
  static const String safe = 'Safe';
  static const String recentAlerts = 'Recent Alerts';
  static const String viewAll = 'View All';
  static const String noAlertsYet = 'No alerts yet';
  static const String startMonitoring = 'Start receiving SMS to begin fraud detection';

  // Risk Levels
  static const String riskLevelSafe = 'SAFE';
  static const String riskLevelSuspicious = 'SUSPICIOUS';
  static const String riskLevelFraud = 'FRAUD';

  // Alert Screen
  static const String alertDetails = 'Alert Details';
  static const String sender = 'Sender';
  static const String timestamp = 'Timestamp';
  static const String riskScore = 'Risk Score';
  static const String messageContent = 'Message Content';
  static const String detectedUrls = 'Detected URLs';
  static const String triggeredRules = 'Triggered Rules';
  static const String analysisBreakdown = 'Analysis Breakdown';
  static const String nlpScore = 'NLP Score';
  static const String domainScore = 'Domain Score';
  static const String ruleScore = 'Rule Score';
  static const String markAsSafe = 'Mark as Safe';
  static const String reportFraud = 'Report Fraud';
  static const String addToTrusted = 'Add to Trusted Senders';

  // Permissions
  static const String permissionsRequired = 'Permissions Required';
  static const String smsPermissionTitle = 'SMS Permission';
  static const String smsPermissionDesc = 'Required to read and analyze incoming SMS messages for fraud detection';
  static const String notificationPermissionTitle = 'Notification Permission';
  static const String notificationPermissionDesc = 'Required to alert you when fraudulent SMS is detected';
  static const String grantPermissions = 'Grant Permissions';
  static const String permissionDenied = 'Permission Denied';

  // Notifications
  static const String fraudAlertTitle = 'Fraud Alert!';
  static const String suspiciousAlertTitle = 'Suspicious Message';
  static const String tapToView = 'Tap to view details';

  // Settings
  static const String settings = 'Settings';
  static const String trustedSenders = 'Trusted Senders';
  static const String detectionHistory = 'Detection History';
  static const String clearHistory = 'Clear History';
  static const String about = 'About';

  // Actions
  static const String analyze = 'Analyze';
  static const String dismiss = 'Dismiss';
  static const String cancel = 'Cancel';
  static const String confirm = 'Confirm';
  static const String delete = 'Delete';
  static const String save = 'Save';

  // Errors
  static const String errorOccurred = 'An error occurred';
  static const String tryAgain = 'Try Again';
  static const String noInternetConnection = 'No internet connection';
  static const String offlineMode = 'Running in offline mode';

  // Analysis Status
  static const String analyzing = 'Analyzing...';
  static const String analysisComplete = 'Analysis Complete';

  // Domain Intelligence
  static const String domainAnalysis = 'Domain Analysis';
  static const String redirectChain = 'Redirect Chain';
  static const String domainAge = 'Domain Age';
  static const String dnsRecords = 'DNS Records';
  static const String whoisInfo = 'WHOIS Info';
  static const String newDomain = 'Newly Registered';
  static const String suspiciousTld = 'Suspicious TLD';
  static const String brandImpersonation = 'Brand Impersonation';

  // Stats
  static const String today = 'Today';
  static const String thisWeek = 'This Week';
  static const String thisMonth = 'This Month';
  static const String allTime = 'All Time';
}
