// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:uuid/uuid.dart';
import '../brand.dart';
import '../models/email.dart';
import 'database_service.dart' if (dart.library.html) 'database_service_web.dart';
import 'encryption_service.dart';
import 'connectivity_service.dart';
import 'offline_queue.dart';

class EmailService {
  static final EmailService _instance = EmailService._internal();
  factory EmailService() => _instance;
  EmailService._internal();

  final DatabaseService _db = DatabaseService();
  final EncryptionService _encryption = EncryptionService();
  final ConnectivityService _connectivity = ConnectivityService();
  final OfflineQueue _offlineQueue = OfflineQueue();
  final Uuid _uuid = const Uuid();

  Future<List<EmailAccount>> getAccounts() async {
    return await _db.getEmailAccounts();
  }

  Future<EmailAccount?> getDefaultAccount() async {
    final accounts = await getAccounts();
    return accounts.where((a) => a.isDefault).firstOrNull ?? accounts.firstOrNull;
  }

  Future<EmailAccount> addImapAccount({
    required String email,
    required String password,
    required String imapHost,
    required int imapPort,
    required String smtpHost,
    required int smtpPort,
    String? displayName,
  }) async {
    final id = _uuid.v4();

    final credentialKey = await _encryption.storeEmailCredentials(
      email: email,
      password: password,
      provider: 'imap',
      imapHost: imapHost,
      imapPort: imapPort,
      smtpHost: smtpHost,
      smtpPort: smtpPort,
    );

    final account = EmailAccount(
      id: id,
      email: email,
      displayName: displayName,
      type: EmailAccountType.imap,
      imapHost: imapHost,
      imapPort: imapPort,
      smtpHost: smtpHost,
      smtpPort: smtpPort,
      isDefault: (await getAccounts()).isEmpty,
      createdAt: DateTime.now(),
    );

    await _db.insertEmailAccount(account, credentialKey: credentialKey);

    await _createDefaultFolders(id);

    return account;
  }

  Future<void> _createDefaultFolders(String accountId) async {
    final folders = [
      EmailFolder(
        id: _uuid.v4(),
        accountId: accountId,
        name: 'Posteingang',
        path: 'INBOX',
        isSystem: true,
      ),
      EmailFolder(
        id: _uuid.v4(),
        accountId: accountId,
        name: 'Gesendet',
        path: 'Sent',
        isSystem: true,
      ),
      EmailFolder(
        id: _uuid.v4(),
        accountId: accountId,
        name: 'Entwürfe',
        path: 'Drafts',
        isSystem: true,
      ),
      EmailFolder(
        id: _uuid.v4(),
        accountId: accountId,
        name: 'Papierkorb',
        path: 'Trash',
        isSystem: true,
      ),
      EmailFolder(
        id: _uuid.v4(),
        accountId: accountId,
        name: 'Spam',
        path: 'Spam',
        isSystem: true,
      ),
    ];

    for (final folder in folders) {
      await _db.insertEmailFolder(folder);
    }
  }

  Future<void> removeAccount(String accountId) async {
    final credentialKey = await _db.getEmailAccountCredentialKey(accountId);
    await _db.deleteEmailAccount(accountId);
    if (credentialKey != null) {
      await _encryption.deleteCredential(credentialKey);
    }
    await _encryption.deleteCredential('email_$accountId');
  }

  Future<List<EmailFolder>> getFolders(String accountId) async {
    return await _db.getEmailFolders(accountId);
  }

  Future<EmailFolder?> getInboxFolder(String accountId) async {
    final folders = await getFolders(accountId);
    return folders.where((f) => f.path == 'INBOX').firstOrNull;
  }

  Future<List<Email>> getEmails({
    required String accountId,
    required String folderId,
    int limit = 50,
    int offset = 0,
  }) async {
    return await _db.getCachedEmails(
      accountId: accountId,
      folderId: folderId,
      limit: limit,
      offset: offset,
    );
  }

  Future<Email?> getEmail(String id) async {
    return await _db.getCachedEmail(id);
  }

  Future<void> markAsRead(String emailId) async {
    final email = await getEmail(emailId);
    if (email != null && !email.isRead) {
      final updated = email.copyWith(isRead: true);
      await _db.updateCachedEmail(updated);

      if (_connectivity.isOnline.value) {

      } else {
        await _offlineQueue.enqueue(
          operationType: OperationType.update,
          entityType: EntityType.email,
          entityId: emailId,
          payload: {'is_read': true},
        );
      }
    }
  }

  Future<void> markAsUnread(String emailId) async {
    final email = await getEmail(emailId);
    if (email != null && email.isRead) {
      final updated = email.copyWith(isRead: false);
      await _db.updateCachedEmail(updated);

      if (_connectivity.isOnline.value) {

      } else {
        await _offlineQueue.enqueue(
          operationType: OperationType.update,
          entityType: EntityType.email,
          entityId: emailId,
          payload: {'is_read': false},
        );
      }
    }
  }

  Future<void> toggleStar(String emailId) async {
    final email = await getEmail(emailId);
    if (email != null) {
      final updated = email.copyWith(isStarred: !email.isStarred);
      await _db.updateCachedEmail(updated);

      if (_connectivity.isOnline.value) {

      } else {
        await _offlineQueue.enqueue(
          operationType: OperationType.update,
          entityType: EntityType.email,
          entityId: emailId,
          payload: {'is_starred': updated.isStarred},
        );
      }
    }
  }

  Future<void> moveToTrash(String emailId) async {
    final email = await getEmail(emailId);
    if (email != null) {
      final folders = await getFolders(email.accountId);
      final trashFolder = folders.where((f) => f.path == 'Trash').firstOrNull;

      if (trashFolder != null) {
        final updated = email.copyWith(folderId: trashFolder.id);
        await _db.updateCachedEmail(updated);

        if (_connectivity.isOnline.value) {

        } else {
          await _offlineQueue.enqueue(
            operationType: OperationType.delete,
            entityType: EntityType.email,
            entityId: emailId,
          );
        }
      }
    }
  }

  Future<void> deleteEmail(String emailId) async {
    await _db.deleteCachedEmail(emailId);

    if (!_connectivity.isOnline.value) {
      await _offlineQueue.enqueue(
        operationType: OperationType.delete,
        entityType: EntityType.email,
        entityId: emailId,
      );
    }
  }

  Future<bool> sendEmail(EmailDraft draft) async {
    if (!_connectivity.isOnline.value) {

      await _offlineQueue.enqueue(
        operationType: OperationType.create,
        entityType: EntityType.email,
        entityId: draft.id ?? _uuid.v4(),
        payload: draft.toMap(),
      );
      return true;
    }

    return true;
  }

  Future<void> syncAccount(String accountId) async {
    if (!_connectivity.isOnline.value) return;

    final account = (await getAccounts()).where((a) => a.id == accountId).firstOrNull;
    if (account == null) return;

    await _addSampleEmails(accountId);

    final updated = account.copyWith(lastSyncAt: DateTime.now());
    await _db.updateEmailAccount(updated);
  }

  Future<void> _addSampleEmails(String accountId) async {
    final folders = await getFolders(accountId);
    final inbox = folders.where((f) => f.path == 'INBOX').firstOrNull;
    if (inbox == null) return;

    final existingEmails = await getEmails(
      accountId: accountId,
      folderId: inbox.id,
      limit: 1,
    );
    if (existingEmails.isNotEmpty) return;

    final sampleEmails = [
      Email(
        id: _uuid.v4(),
        accountId: accountId,
        folderId: inbox.id,
        subject: 'Willkommen bei ${Brand.name} E-Mail',
        from: 'team@example.com',
        fromName: '${Brand.name} Team',
        to: ['user@example.com'],
        bodyPlain: 'Herzlich willkommen! Dein E-Mail-Konto wurde erfolgreich eingerichtet. Du kannst jetzt E-Mails empfangen und senden - auch offline! Deine Nachrichten werden synchronisiert, sobald du wieder online bist.',
        date: DateTime.now().subtract(const Duration(hours: 1)),
        isRead: false,
      ),
      Email(
        id: _uuid.v4(),
        accountId: accountId,
        folderId: inbox.id,
        subject: 'Aufgaben für diese Woche',
        from: 'schule@example.de',
        fromName: 'Schule',
        to: ['user@example.com'],
        bodyPlain: 'Hier sind deine Aufgaben für diese Woche:\n\n1. Mathematik: Seite 45-48\n2. Deutsch: Aufsatz schreiben\n3. Englisch: Vokabeln lernen\n\nViel Erfolg!',
        date: DateTime.now().subtract(const Duration(hours: 3)),
        isRead: false,
      ),
      Email(
        id: _uuid.v4(),
        accountId: accountId,
        folderId: inbox.id,
        subject: 'Termin: Elternabend',
        from: 'sekretariat@schule.de',
        fromName: 'Sekretariat',
        to: ['user@example.com'],
        bodyPlain: 'Liebe Eltern,\n\nwir laden Sie herzlich zum Elternabend am kommenden Donnerstag um 19:00 Uhr ein.\n\nMit freundlichen Grüßen\nDas Sekretariat',
        date: DateTime.now().subtract(const Duration(days: 1)),
        isRead: true,
      ),
    ];

    for (final email in sampleEmails) {
      await _db.insertCachedEmail(email);
    }

    final updatedInbox = inbox.copyWith(
      unreadCount: sampleEmails.where((e) => !e.isRead).length,
      totalCount: sampleEmails.length,
    );
    await _db.updateEmailFolder(updatedInbox);
  }

  Future<List<Email>> searchEmails({
    required String accountId,
    required String query,
    String? folderId,
  }) async {
    final allEmails = folderId != null
        ? await getEmails(accountId: accountId, folderId: folderId, limit: 1000)
        : await _db.getCachedEmails(accountId: accountId, folderId: '', limit: 1000);

    final lowerQuery = query.toLowerCase();
    return allEmails.where((email) {
      return email.subject.toLowerCase().contains(lowerQuery) ||
             email.from.toLowerCase().contains(lowerQuery) ||
             (email.fromName?.toLowerCase().contains(lowerQuery) ?? false) ||
             (email.bodyPlain?.toLowerCase().contains(lowerQuery) ?? false);
    }).toList();
  }

  Future<int> getUnreadCount(String accountId) async {
    final folders = await getFolders(accountId);
    int total = 0;
    for (final folder in folders) {
      total += folder.unreadCount;
    }
    return total;
  }

  Future<Map<String, int>> getFolderCounts(String accountId) async {
    final folders = await getFolders(accountId);
    final counts = <String, int>{};
    for (final folder in folders) {
      counts[folder.name] = folder.unreadCount;
    }
    return counts;
  }
}
