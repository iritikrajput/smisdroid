import 'package:sqflite/sqflite.dart' show Database, Sqflite, openDatabase, getDatabasesPath, ConflictAlgorithm;
import 'package:path/path.dart';
import '../models/sms_analysis_result.dart';

class DatabaseService {
  static Database? _db;

  static Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'smisdroid.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE fraud_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sender TEXT,
            risk_level TEXT,
            risk_score REAL,
            urls TEXT,
            rules TEXT,
            domain_score INTEGER,
            nlp_score REAL,
            timestamp TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE trusted_senders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sender TEXT UNIQUE,
            added_at TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE domain_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            domain TEXT UNIQUE,
            is_phishing INTEGER,
            score INTEGER,
            cached_at TEXT
          )
        ''');
      },
    );
  }

  static Future<void> logResult(SmsAnalysisResult result) async {
    final db = await database;
    await db.insert('fraud_logs', {
      'sender': result.sender,
      'risk_level': result.riskLevel,
      'risk_score': result.riskScore,
      'urls': result.detectedUrls.join(','),
      'rules': result.triggeredRules.join('|'),
      'domain_score': result.domainScore,
      'nlp_score': result.nlpScore,
      'timestamp': result.timestamp.toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> getRecentLogs({
    int limit = 50,
  }) async {
    final db = await database;
    return db.query('fraud_logs', orderBy: 'id DESC', limit: limit);
  }

  static Future<Map<String, int>> getStats() async {
    final db = await database;
    final total =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM fraud_logs'),
        ) ??
        0;
    final fraud =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM fraud_logs WHERE risk_level='FRAUD'",
          ),
        ) ??
        0;
    final suspicious =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM fraud_logs WHERE risk_level='SUSPICIOUS'",
          ),
        ) ??
        0;
    return {
      'total': total,
      'fraud': fraud,
      'suspicious': suspicious,
      'safe': total - fraud - suspicious,
    };
  }

  // Trusted Senders
  static Future<bool> isTrustedSender(String sender) async {
    final db = await database;
    final result = await db.query(
      'trusted_senders',
      where: 'sender = ?',
      whereArgs: [sender],
    );
    return result.isNotEmpty;
  }

  static Future<void> addTrustedSender(String sender) async {
    final db = await database;
    await db.insert(
      'trusted_senders',
      {
        'sender': sender,
        'added_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<void> removeTrustedSender(String sender) async {
    final db = await database;
    await db.delete(
      'trusted_senders',
      where: 'sender = ?',
      whereArgs: [sender],
    );
  }

  static Future<List<String>> getTrustedSenders() async {
    final db = await database;
    final result = await db.query('trusted_senders');
    return result.map((r) => r['sender'] as String).toList();
  }

  // Domain Cache
  static Future<Map<String, dynamic>?> getCachedDomain(String domain) async {
    final db = await database;
    final result = await db.query(
      'domain_cache',
      where: 'domain = ?',
      whereArgs: [domain],
    );
    if (result.isEmpty) return null;

    // Check if cache is still valid (24 hours)
    final cachedAt = DateTime.parse(result.first['cached_at'] as String);
    if (DateTime.now().difference(cachedAt).inHours > 24) {
      await db.delete('domain_cache', where: 'domain = ?', whereArgs: [domain]);
      return null;
    }

    return result.first;
  }

  static Future<void> cacheDomain({
    required String domain,
    required bool isPhishing,
    required int score,
  }) async {
    final db = await database;
    await db.insert(
      'domain_cache',
      {
        'domain': domain,
        'is_phishing': isPhishing ? 1 : 0,
        'score': score,
        'cached_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> clearCache() async {
    final db = await database;
    await db.delete('domain_cache');
  }

  static Future<void> clearHistory() async {
    final db = await database;
    await db.delete('fraud_logs');
  }
}
