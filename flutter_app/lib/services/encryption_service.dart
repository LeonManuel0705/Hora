// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  Future<void> storeCredential(String key, String value) async {
    await _secureStorage.write(key: key, value: value);
  }

  Future<String?> getCredential(String key) async {
    return await _secureStorage.read(key: key);
  }

  Future<void> deleteCredential(String key) async {
    await _secureStorage.delete(key: key);
  }

  Future<void> deleteCredentialsWithPrefix(String prefix, {String? keep}) async {
    final keys = (await _secureStorage.readAll()).keys.where((key) => key.startsWith(prefix) && key != keep);
    for (final key in keys.toList()) {
      try {
        await _secureStorage.delete(key: key);
      } catch (_) {}
    }
  }

  Future<bool> hasCredential(String key) async {
    final value = await _secureStorage.read(key: key);
    return value != null;
  }

  Future<String> storeIServCredentials({
    required String username,
    required String password,
    required String iservUrl,
  }) async {
    final credentialKey = 'iserv_${_hashString(username)}';
    final credentials = jsonEncode({
      'username': username,
      'password': password,
      'iserv_url': iservUrl,
    });
    await storeCredential(credentialKey, credentials);
    return credentialKey;
  }

  Future<Map<String, String>?> getIServCredentials(String credentialKey) async {
    final credentials = await getCredential(credentialKey);
    if (credentials == null) return null;
    final decoded = jsonDecode(credentials) as Map<String, dynamic>;
    return {
      'username': decoded['username'] as String,
      'password': decoded['password'] as String,
      'iserv_url': decoded['iserv_url'] as String,
    };
  }

  Future<String> storeEmailCredentials({
    required String email,
    required String password,
    required String provider,
    String? imapHost,
    int? imapPort,
    String? smtpHost,
    int? smtpPort,
  }) async {
    final credentialKey = 'email_${_hashString(email)}';
    final credentials = jsonEncode({
      'email': email,
      'password': password,
      'provider': provider,
      'imap_host': imapHost,
      'imap_port': imapPort,
      'smtp_host': smtpHost,
      'smtp_port': smtpPort,
    });
    await storeCredential(credentialKey, credentials);
    return credentialKey;
  }

  Future<Map<String, dynamic>?> getEmailCredentials(String credentialKey) async {
    final credentials = await getCredential(credentialKey);
    if (credentials == null) return null;
    return jsonDecode(credentials) as Map<String, dynamic>;
  }

  Future<void> storeGoogleTokens({
    required String email,
    required String accessToken,
    String? refreshToken,
    DateTime? expiresAt,
  }) async {
    final tokenKey = 'google_token_${_hashString(email)}';
    final tokens = jsonEncode({
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'expires_at': expiresAt?.toIso8601String(),
    });
    await storeCredential(tokenKey, tokens);
  }

  Future<Map<String, dynamic>?> getGoogleTokens(String email) async {
    final tokenKey = 'google_token_${_hashString(email)}';
    var tokens = await getCredential(tokenKey);
    if (tokens == null) {
      final legacyKey = 'google_token_${_legacyHashString(email)}';
      tokens = await getCredential(legacyKey);
      if (tokens != null) {
        await storeCredential(tokenKey, tokens);
        await deleteCredential(legacyKey);
      }
    }
    if (tokens == null) return null;
    return jsonDecode(tokens) as Map<String, dynamic>;
  }

  Future<void> deleteGoogleTokens(String email) async {
    await deleteCredential('google_token_${_hashString(email)}');
    await deleteCredential('google_token_${_legacyHashString(email)}');
  }

  Future<void> deleteEmailCredentials(String email) async {
    await deleteCredential('email_${_hashString(email)}');
  }

  Future<void> clearAccountCredentials(String accountId) async {
    for (final hash in [_hashString(accountId), _legacyHashString(accountId)]) {
      await deleteCredential('iserv_$hash');
      await deleteCredential('email_$hash');
      await deleteCredential('google_token_$hash');
    }
  }

  Future<void> clearAllCredentials() async {
    await _secureStorage.deleteAll();
  }

  String _hashString(String input) {
    final bytes = utf8.encode(input.toLowerCase());
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  String _legacyHashString(String input) {
    final bytes = utf8.encode(input.toLowerCase());
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }

  Future<Map<String, String>> getAllKeys() async {
    assert(kDebugMode, 'getAllKeys() must not be called in release builds');
    if (!kDebugMode) return {};
    return await _secureStorage.readAll();
  }
}
