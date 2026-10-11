import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/profile/backup/account_archive.dart';
import 'package:intl/intl.dart';

/// Exports all of the user's data as one JSON file, saved wherever the user
/// picks via the native `BackupExportPlugin`. Two parts:
///
/// * `account`: the complete history from the api ([AccountArchive]), which
///   reaches further back than the device keeps.
/// * `device`: every [FlutterSecureStorage] entry under its original key, so
///   the device-only state (sensor and pod pairing, local settings) comes along
///   and a restore only has to write each one back. The login tokens are left
///   out, because the file leaves the keystore unencrypted and a restored
///   device signs in again anyway.
class DataBackup {
  static const _channel = MethodChannel('insulink/backup_export');
  static const formatVersion = 1;
  static const _sessionKeys = {'authentication_token', 'refresh_token'};

  final FlutterSecureStorage _storage;

  const DataBackup([this._storage = const FlutterSecureStorage()]);

  /// The backup document: format marker, creation time (epoch ms), the
  /// downloaded [account] history and every stored entry except the session
  /// tokens.
  Future<Map<String, Object>> collect(
    DateTime now,
    Map<String, Object> account,
  ) async {
    final entries = await _storage.readAll();
    entries.removeWhere((key, value) => _sessionKeys.contains(key));
    return {
      'format': 'insulink_backup',
      'version': formatVersion,
      'created_at': now.millisecondsSinceEpoch,
      'account': account,
      'device': entries,
    };
  }

  /// Opens the save dialog with the backup. True once the file is written,
  /// false when the user cancelled; a failed download or write throws.
  Future<bool> export() async {
    final now = DateTime.now();
    final account = await const AccountArchive().download();
    final content = jsonEncode(await collect(now, account));
    final name = 'insulink-backup-${DateFormat('yyyy-MM-dd').format(now)}.json';
    final saved = await _channel.invokeMethod<bool>('save', {
      'name': name,
      'content': content,
    });
    return saved ?? false;
  }
}
