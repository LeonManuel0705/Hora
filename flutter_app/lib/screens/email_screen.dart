// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only


import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/email_provider.dart';
import '../models/email.dart';
import '../theme.dart';
import '../widgets/page_fade_in.dart';

class EmailScreen extends StatefulWidget {
  const EmailScreen({super.key});

  @override
  State<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends State<EmailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EmailProvider>().initialize();
    });
  }

  void _showAddAccountDialog() {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final imapHostController = TextEditingController();
    final smtpHostController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppPalette.surfaceDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppPalette.ring,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.email, color: AppTheme.primaryColor, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'E-Mail-Konto hinzufügen',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildTextField(
                  controller: emailController,
                  label: 'E-Mail-Adresse',
                  hint: 'beispiel@mail.de',
                  icon: Icons.email,
                  isDark: isDark,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: passwordController,
                  label: 'Passwort',
                  hint: '',
                  icon: Icons.lock,
                  isDark: isDark,
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: imapHostController,
                  label: 'IMAP Server',
                  hint: 'imap.mail.de',
                  icon: Icons.dns,
                  isDark: isDark,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: smtpHostController,
                  label: 'SMTP Server',
                  hint: 'smtp.mail.de',
                  icon: Icons.send,
                  isDark: isDark,
                ),
                const SizedBox(height: 24),
                Consumer<EmailProvider>(
                  builder: (context, provider, child) {
                    return SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: provider.isLoading
                            ? null
                            : () async {
                                if (emailController.text.trim().isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Bitte E-Mail-Adresse eingeben'),
                                      backgroundColor: AppTheme.danger,
                                    ),
                                  );
                                  return;
                                }
                                if (!emailController.text.contains('@')) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Bitte gültige E-Mail-Adresse eingeben'),
                                      backgroundColor: AppTheme.danger,
                                    ),
                                  );
                                  return;
                                }
                                if (passwordController.text.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Bitte Passwort eingeben'),
                                      backgroundColor: AppTheme.danger,
                                    ),
                                  );
                                  return;
                                }
                                if (imapHostController.text.trim().isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Bitte IMAP Server eingeben'),
                                      backgroundColor: AppTheme.danger,
                                    ),
                                  );
                                  return;
                                }
                                if (smtpHostController.text.trim().isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Bitte SMTP Server eingeben'),
                                      backgroundColor: AppTheme.danger,
                                    ),
                                  );
                                  return;
                                }

                                final success = await provider.addAccount(
                                  email: emailController.text.trim(),
                                  password: passwordController.text,
                                  imapHost: imapHostController.text.trim(),
                                  imapPort: 993,
                                  smtpHost: smtpHostController.text.trim(),
                                  smtpPort: 587,
                                );
                                if (success && context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('E-Mail-Konto erfolgreich hinzugefügt'),
                                      backgroundColor: AppTheme.success,
                                    ),
                                  );
                                } else if (!success && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(provider.error ?? 'Fehler beim Hinzufügen des Kontos'),
                                      backgroundColor: AppTheme.danger,
                                    ),
                                  );
                                }
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: provider.isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Hinzufügen'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      emailController.dispose();
      passwordController.dispose();
      imapHostController.dispose();
      smtpHostController.dispose();
    });
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool isDark,
    bool obscureText = false,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppPalette.lineDark : AppPalette.line,
        ),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        autocorrect: !obscureText,
        enableSuggestions: !obscureText,
        keyboardType: keyboardType,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: isDark ? Colors.white54 : Colors.black54),
          labelStyle: TextStyle(
            color: isDark ? Colors.white54 : Colors.black54,
          ),
          hintStyle: TextStyle(
            color: isDark ? Colors.white38 : Colors.black38,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }

  void _showComposeDialog({String? to, String? subject, String? body}) {
    final toController = TextEditingController(text: to ?? '');
    final subjectController = TextEditingController(text: subject ?? '');
    final bodyController = TextEditingController(text: body ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: BoxDecoration(
            color: isDark ? AppPalette.surfaceDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Neue E-Mail',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    Consumer<EmailProvider>(
                      builder: (context, provider, child) {
                        return FilledButton.icon(
                          onPressed: () async {
                            final account = provider.selectedAccount;
                            if (account != null) {
                              final draft = EmailDraft(
                                accountId: account.id,
                                subject: subjectController.text,
                                to: toController.text.split(',').map((e) => e.trim()).toList(),
                                body: bodyController.text,
                                createdAt: DateTime.now(),
                                updatedAt: DateTime.now(),
                              );
                              final success = await provider.sendEmail(draft);
                              if (success && context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('E-Mail wurde gesendet')),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.send, size: 18),
                          label: const Text('Senden'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildTextField(
                      controller: toController,
                      label: 'An',
                      hint: 'empfaenger@mail.de',
                      icon: Icons.person,
                      isDark: isDark,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: subjectController,
                      label: 'Betreff',
                      hint: '',
                      icon: Icons.subject,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      height: 300,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? AppPalette.lineDark : AppPalette.line,
                        ),
                      ),
                      child: TextField(
                        controller: bodyController,
                        maxLines: null,
                        expands: true,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Nachricht schreiben...',
                          hintStyle: TextStyle(
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ).then((_) {
      toController.dispose();
      subjectController.dispose();
      bodyController.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PageFadeIn(
      child: Stack(
        children: [
          Consumer<EmailProvider>(
            builder: (context, provider, child) {
              if (provider.isLoading && !provider.hasAccounts) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!provider.hasAccounts) {
              return _NoAccountView(
                onAddAccount: _showAddAccountDialog,
                isDark: isDark,
              );
            }

            if (provider.selectedEmail != null) {
              return _EmailDetailView(
                email: provider.selectedEmail!,
                onBack: () => provider.clearSelectedEmail(),
                isDark: isDark,
                onReply: (email) {
                  final bodyText = email.bodyPlain ?? email.bodyHtml?.replaceAll(RegExp(r'<[^>]*>'), '') ?? '';
                  final quotedBody = '\n\n--- Ursprüngliche Nachricht ---\nVon: ${email.displayFrom}\nDatum: ${email.date}\n\n$bodyText';
                  final replySubject = email.subject.startsWith('Re: ') ? email.subject : 'Re: ${email.subject}';
                  _showComposeDialog(
                    to: email.from,
                    subject: replySubject,
                    body: quotedBody,
                  );
                },
                onForward: (email) {
                  final bodyText = email.bodyPlain ?? email.bodyHtml?.replaceAll(RegExp(r'<[^>]*>'), '') ?? '';
                  final quotedBody = '\n\n--- Weitergeleitete Nachricht ---\nVon: ${email.displayFrom}\nDatum: ${email.date}\nBetreff: ${email.subject}\n\n$bodyText';
                  final fwdSubject = email.subject.startsWith('Fwd: ') ? email.subject : 'Fwd: ${email.subject}';
                  _showComposeDialog(
                    subject: fwdSubject,
                    body: quotedBody,
                  );
                },
              );
            }

            return _EmailListView(
              emails: provider.filteredEmails,
              isLoading: provider.isLoading,
              onEmailTap: (email) => provider.selectEmail(email),
              onRefresh: () => provider.syncCurrentAccount(),
              isDark: isDark,
              provider: provider,
              onAddAccount: _showAddAccountDialog,
            );
            },
          ),

          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 16,
            child: Consumer<EmailProvider>(
              builder: (context, provider, child) {
                if (!provider.hasAccounts) {
                  return FloatingActionButton.extended(
                    heroTag: 'fab_email_add',
                    onPressed: _showAddAccountDialog,
                    backgroundColor: AppTheme.primaryColor,
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('Konto hinzufügen', style: TextStyle(color: Colors.white)),
                  );
                }
                return FloatingActionButton(
                  heroTag: 'fab_email_compose',
                  onPressed: _showComposeDialog,
                  backgroundColor: AppTheme.primaryColor,
                  child: const Icon(Icons.edit, color: Colors.white),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NoAccountView extends StatelessWidget {
  final VoidCallback onAddAccount;
  final bool isDark;

  const _NoAccountView({required this.onAddAccount, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? AppPalette.surfaceDark : AppPalette.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? AppPalette.lineDark : AppPalette.line,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.email, color: AppTheme.primaryColor, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'E-Mail',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        Text(
                          'Verwalte deine E-Mails',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ),

        const SizedBox(height: 80),

        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: isDark ? AppPalette.surfaceDark : AppPalette.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? AppPalette.lineDark : AppPalette.line,
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.email_outlined,
                      size: 56,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Kein E-Mail-Konto',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Füge ein E-Mail-Konto hinzu, um deine Nachrichten offline zu lesen und zu verwalten.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: onAddAccount,
                    icon: const Icon(Icons.add),
                    label: const Text('Konto hinzufügen'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
        ),

        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Schnellzugriff',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 2.2,
          children: [
            const _EmailQuickLink(name: 'Gmail', color: Color(0xFFEA4335), icon: Icons.mail),
            const _EmailQuickLink(name: 'Outlook', color: Color(0xFF0078D4), icon: Icons.mail),
            _EmailQuickLink(name: 'ProtonMail', color: AppTheme.primaryLight, icon: Icons.shield),
            const _EmailQuickLink(name: 'Yahoo', color: Color(0xFF6001D2), icon: Icons.mail),
          ],
        ),
      ],
    );
  }
}

class _EmailQuickLink extends StatelessWidget {
  final String name;
  final Color color;
  final IconData icon;

  const _EmailQuickLink({required this.name, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final urls = {
      'Gmail': 'https://mail.google.com',
      'Outlook': 'https://outlook.live.com',
      'ProtonMail': 'https://mail.proton.me',
      'Yahoo': 'https://mail.yahoo.com',
    };
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          final url = urls[name];
          if (url != null) {
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          }
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? AppPalette.surfaceDark : AppPalette.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? AppPalette.lineDark : AppPalette.line,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmailListView extends StatelessWidget {
  final List<Email> emails;
  final bool isLoading;
  final void Function(Email) onEmailTap;
  final VoidCallback onRefresh;
  final bool isDark;
  final EmailProvider provider;
  final VoidCallback onAddAccount;

  const _EmailListView({
    required this.emails,
    required this.isLoading,
    required this.onEmailTap,
    required this.onRefresh,
    required this.isDark,
    required this.provider,
    required this.onAddAccount,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? AppPalette.surfaceDark : AppPalette.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? AppPalette.lineDark : AppPalette.line,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.email, color: AppTheme.primaryColor, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'E-Mail',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          Text(
                            provider.selectedAccount?.email ?? 'Verwalte deine E-Mails',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (provider.isSyncing)
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      IconButton(
                        icon: Icon(Icons.refresh, color: isDark ? Colors.white70 : Colors.black54),
                        onPressed: onRefresh,
                      ),
                  ],
                ),
              ),
          ),

          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(child: _buildStatCard(
                context,
                isDark: isDark,
                icon: Icons.inbox,
                value: '${emails.length}',
                label: 'E-Mails',
                color: AppTheme.primaryColor,
              )),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard(
                context,
                isDark: isDark,
                icon: Icons.mark_email_unread,
                value: '${emails.where((e) => !e.isRead).length}',
                label: 'Ungelesen',
                color: AppTheme.info,
              )),
            ],
          ),

          const SizedBox(height: 24),

          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.inbox, size: 16, color: AppTheme.primaryColor),
              ),
              const SizedBox(width: 10),
              Text(
                'Posteingang',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (isLoading && emails.isEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: isDark ? AppPalette.surfaceDark : AppPalette.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? AppPalette.lineDark : AppPalette.line,
                    ),
                  ),
                  child: const Center(child: CircularProgressIndicator()),
                ),
            )
          else if (emails.isEmpty)
            _buildEmptyState(context, isDark)
          else
            ...emails.map((email) => _EmailListItem(
              email: email,
              onTap: () => onEmailTap(email),
              isDark: isDark,
            )),

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required bool isDark,
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppPalette.surfaceDark : AppPalette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? AppPalette.lineDark : AppPalette.line,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: isDark ? AppPalette.surfaceDark : AppPalette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? AppPalette.lineDark : AppPalette.line,
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons.inbox_outlined,
                size: 48,
                color: isDark ? Colors.white38 : Colors.black26,
              ),
              const SizedBox(height: 12),
              Text(
                'Keine E-Mails',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Ziehe zum Aktualisieren nach unten',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            ],
          ),
        ),
    );
  }
}

class _EmailListItem extends StatelessWidget {
  final Email email;
  final VoidCallback onTap;
  final bool isDark;

  const _EmailListItem({
    required this.email,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
            decoration: BoxDecoration(
              color: isDark ? AppPalette.surfaceDark : AppPalette.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppPalette.lineDark : AppPalette.line,
              ),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: email.isRead
                            ? (isDark ? AppPalette.lineDark : AppPalette.line)
                            : AppTheme.primaryColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          (email.displayFrom.isNotEmpty ? email.displayFrom[0] : '?').toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: email.isRead
                                ? (isDark ? Colors.white54 : Colors.black54)
                                : AppTheme.primaryColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  email.displayFrom,
                                  style: TextStyle(
                                    fontWeight: email.isRead ? FontWeight.normal : FontWeight.bold,
                                    fontSize: 14,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                _formatDate(email.date),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white54 : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            email.subject,
                            style: TextStyle(
                              fontWeight: email.isRead ? FontWeight.normal : FontWeight.w600,
                              fontSize: 14,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            email.preview,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (email.isStarred)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.star,
                          size: 20,
                          color: AppPalette.amber,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 60) {
      return 'vor ${diff.inMinutes} Min.';
    } else if (diff.inHours < 24) {
      return 'vor ${diff.inHours} Std.';
    } else if (diff.inDays < 7) {
      return 'vor ${diff.inDays} Tagen';
    } else {
      return '${date.day}.${date.month}.';
    }
  }
}

class _EmailDetailView extends StatelessWidget {
  final Email email;
  final VoidCallback onBack;
  final bool isDark;
  final void Function(Email) onReply;
  final void Function(Email) onForward;

  const _EmailDetailView({
    required this.email,
    required this.onBack,
    required this.isDark,
    required this.onReply,
    required this.onForward,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? AppPalette.surfaceDark : AppPalette.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? AppPalette.lineDark : AppPalette.line,
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.black87),
                      onPressed: onBack,
                    ),
                    const Spacer(),
                    Consumer<EmailProvider>(
                      builder: (context, provider, child) {
                        return Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                email.isStarred ? Icons.star : Icons.star_border,
                                color: email.isStarred ? AppPalette.amber : (isDark ? Colors.white70 : Colors.black54),
                              ),
                              onPressed: () => provider.toggleStar(email.id),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline, color: isDark ? Colors.white70 : Colors.black54),
                              onPressed: () {
                                provider.moveToTrash(email.id);
                                onBack();
                              },
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isDark ? AppPalette.surfaceDark : AppPalette.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? AppPalette.lineDark : AppPalette.line,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            email.subject,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 20),

                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    (email.displayFrom.isNotEmpty ? email.displayFrom[0] : '?').toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      email.displayFrom,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                    Text(
                                      email.from,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark ? Colors.white54 : Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                _formatFullDate(email.date),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white54 : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'An: ${email.to.join(', ')}',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Divider(color: isDark ? Colors.white12 : Colors.black12),
                          const SizedBox(height: 16),

                          Text(
                            email.bodyPlain ?? email.bodyHtml?.replaceAll(RegExp(r'<[^>]*>'), '') ?? '',
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.6,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),

                          if (email.hasAttachments && email.attachments != null) ...[
                            const SizedBox(height: 24),
                            Divider(color: isDark ? Colors.white12 : Colors.black12),
                            const SizedBox(height: 16),
                            Text(
                              'Anhänge (${email.attachments!.length})',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...email.attachments!.map((attachment) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.black.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.attachment, color: isDark ? Colors.white54 : Colors.black54),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          attachment.filename,
                                          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                                        ),
                                        Text(
                                          attachment.sizeFormatted,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDark ? Colors.white54 : Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.download, color: AppTheme.primaryColor),
                                ],
                              ),
                            )),
                          ],
                        ],
                      ),
                    ),
                ),

                const SizedBox(height: 16),

                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? AppPalette.surfaceDark : AppPalette.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? AppPalette.lineDark : AppPalette.line,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => onReply(email),
                              icon: const Icon(Icons.reply),
                              label: const Text('Antworten'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => onForward(email),
                              icon: const Icon(Icons.forward),
                              label: const Text('Weiterleiten'),
                            ),
                          ),
                        ],
                      ),
                    ),
                ),

                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatFullDate(DateTime date) {
    final weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final months = ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];

    return '${weekdays[date.weekday - 1]}, ${date.day}. ${months[date.month - 1]} ${date.year}, ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
