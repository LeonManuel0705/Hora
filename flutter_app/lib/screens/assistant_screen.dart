// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/page_fade_in.dart';
import '../services/assistant/assistant_engine.dart';
import '../services/connectivity_service.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});
  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _messages = <_Msg>[];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _busy = false;
  bool _engineReady = false;

  @override
  void initState() {
    super.initState();
    AssistantEngine.instance.initialize().then((_) {
      if (mounted) setState(() => _engineReady = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;

    setState(() {
      _messages.add(_Msg(role: _Role.user, text: text));
      _busy = true;
      _controller.clear();
    });
    _scrollToEnd();

    final online = ConnectivityService().isOnline.value;
    final response = await AssistantEngine.instance.answer(text, online: online);

    if (!mounted) return;
    setState(() {
      _messages.add(_Msg(
        role: _Role.assistant,
        text: response.text,
        source: response.source,
        online: response.online,
      ));
      _busy = false;
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PageFadeIn(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                AppTheme.gradientText('Assistent', fontSize: 36),
                const Spacer(),
                _StatusPill(ready: _engineReady),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Rechnen, Formeln, Daten, Literatur-Epochen und bekannte Werke — '
              'alles offline. Für neue Biografien wird Internet verwendet.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? _EmptyState(onTap: (q) { _controller.text = q; _send(); })
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _messages.length + (_busy ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == _messages.length) return const _TypingIndicator();
                      return _Bubble(msg: _messages[i], isDark: isDark);
                    },
                  ),
          ),
          _InputBar(
            controller: _controller,
            onSubmit: _send,
            enabled: _engineReady && !_busy,
          ),
        ],
      ),
    );
  }
}

enum _Role { user, assistant }

class _Msg {
  _Msg({required this.role, required this.text, this.source, this.online = false});
  final _Role role;
  final String text;
  final AssistantSource? source;
  final bool online;
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg, required this.isDark});
  final _Msg msg;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == _Role.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: BoxDecoration(
            color: isUser
                ? AppTheme.primaryColor.withValues(alpha: 0.18)
                : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04)),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText.rich(
                _markdownSpan(
                  msg.text,
                  TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: isDark ? Colors.white : const Color(0xFF18181B),
                  ),
                ),
              ),
              if (!isUser && msg.source != null && msg.source != AssistantSource.unknown) ...[
                const SizedBox(height: 6),
                Text(
                  _sourceLabel(msg.source!, msg.online),
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _sourceLabel(AssistantSource s, bool online) {
    switch (s) {
      case AssistantSource.math: return '• offline · rechnen';
      case AssistantSource.date: return '• offline · datum';
      case AssistantSource.unit: return '• offline · einheiten';
      case AssistantSource.formula: return '• offline · formelsammlung';
      case AssistantSource.epoch: return '• offline · literaturepochen';
      case AssistantSource.werk: return '• offline · werkliste';
      case AssistantSource.topics: return '• offline · lehrplan';
      case AssistantSource.cached: return '• offline · wikipedia-cache';
      case AssistantSource.wikipedia: return '• online · wikipedia';
      case AssistantSource.unknown: return '';
    }
  }
}

TextSpan _markdownSpan(String text, TextStyle base) {
  final spans = <TextSpan>[];
  final pattern = RegExp(r'\*\*(.+?)\*\*', dotAll: true);
  var last = 0;
  for (final m in pattern.allMatches(text)) {
    if (m.start > last) {
      spans.add(TextSpan(text: text.substring(last, m.start)));
    }
    spans.add(TextSpan(
      text: m.group(1),
      style: const TextStyle(fontWeight: FontWeight.w700),
    ));
    last = m.end;
  }
  if (last < text.length) {
    spans.add(TextSpan(text: text.substring(last)));
  }
  return TextSpan(style: base, children: spans);
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.onSubmit, required this.enabled});
  final TextEditingController controller;
  final VoidCallback onSubmit;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSubmit(),
                inputFormatters: [LengthLimitingTextInputFormatter(500)],
                decoration: InputDecoration(
                  hintText: enabled ? 'Frage stellen…' : 'Bereit in einem Moment…',
                  filled: true,
                  fillColor: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: enabled ? onSubmit : null,
              icon: const Icon(Icons.send_rounded),
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                disabledBackgroundColor: AppTheme.primaryColor.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(
        children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('…', style: TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.ready});
  final bool ready;
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: ready ? const Color(0x2232D160) : const Color(0x22AAAAAA),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ready ? Icons.wifi_off_rounded : Icons.hourglass_empty_rounded,
            size: 12,
            color: ready ? const Color(0xFF32D160) : (isDark ? Colors.white54 : Colors.black54),
          ),
          const SizedBox(width: 4),
          Text(
            ready ? 'offline-ready' : 'lädt…',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ready ? const Color(0xFF32D160) : (isDark ? Colors.white54 : Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onTap});
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const suggestions = [
      'Was ist die Mitternachtsformel?',
      'Ableitung von sin(x)',
      'Wer schrieb Faust?',
      'Merkmale der Romantik',
      '15% von 200',
      'Themen in der 11. Klasse Physik',
      '100 km in meilen',
      'Welcher Wochentag ist der 24.12.2026?',
    ];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 16),
        Center(
          child: GlassCard(
            padding: const EdgeInsets.all(20),
            borderRadius: 20,
            child: Column(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 32, color: AppTheme.primaryColor),
                const SizedBox(height: 10),
                Text(
                  'Frag mich was',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF18181B),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Rechnen, Formeln, Daten, Literatur und Lehrplan — alles offline.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Probier zum Beispiel:', style: TextStyle(
          fontSize: 13, color: isDark ? Colors.white60 : Colors.black54)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in suggestions)
              ActionChip(
                label: Text(s, style: const TextStyle(fontSize: 12)),
                onPressed: () => onTap(s),
                backgroundColor: isDark ? Colors.white10 : Colors.black12,
              ),
          ],
        ),
      ],
    );
  }
}
