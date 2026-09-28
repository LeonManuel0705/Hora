// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/assistant/assistant_chat.dart';
import '../services/assistant/assistant_engine.dart';
import '../services/assistant/local_model/assistant_prompt.dart';
import '../services/assistant/local_model/local_assistant.dart';
import '../services/assistant/local_model/model_format.dart';
import '../services/assistant/local_model/model_installer.dart';
import '../services/connectivity_service.dart';
import '../theme.dart';
import '../widgets/chat_markdown.dart';
import '../widgets/glass_card.dart';
import '../widgets/page_fade_in.dart';
import 'assistant_install_view.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  static const _basicKey = 'assistant_basic_accepted';

  final LocalAssistant? _local = LocalAssistant.instance;
  late final AssistantChat _basicChat = AssistantChat.basic(
    answer: (question) => AssistantEngine.instance.answer(question, online: ConnectivityService().isOnline.value),
  );
  AssistantChat? _modelChat;
  bool _engineReady = false;
  bool _basicAccepted = false;

  @override
  void initState() {
    super.initState();
    AssistantEngine.instance.initialize().then((_) {
      if (mounted) setState(() => _engineReady = true);
    });
    final local = _local;
    if (local != null) {
      local.attach();
      local.installer.addListener(_installChanged);
      unawaited(local.installer.refresh());
      unawaited(SharedPreferences.getInstance().then((prefs) {
        if (mounted && prefs.getBool(_basicKey) == true) setState(() => _basicAccepted = true);
      }));
    }
  }

  @override
  void dispose() {
    final local = _local;
    if (local != null) {
      local.installer.removeListener(_installChanged);
      local.detach();
    }
    _modelChat?.dispose();
    _basicChat.dispose();
    super.dispose();
  }

  void _installChanged() {
    if (mounted) setState(() {});
  }

  AssistantChat _chatFor(LocalAssistant local) => _modelChat ??= AssistantChat.local(
        runtime: local.runtime,
        modelPath: () => local.installer.modelPath,
        exact: (question) =>
            AssistantEngine.instance.answerExact(question, online: ConnectivityService().isOnline.value),
        systemPrompt: () async =>
            buildAssistantSystemPrompt(describeAssistantContext(await loadAssistantContext(DateTime.now()))),
      );

  Future<void> _install({bool retry = false}) async {
    final installer = _local!.installer;
    final result = retry ? await installer.retry() : await installer.install();
    if (result != InstallStart.needsMobileConfirmation || !mounted) return;
    final model = installer.state.model;
    if (model == null) return;
    if (await confirmMobileDownload(context, model.bytes)) {
      await installer.install(allowMobileData: true);
    } else if (installer.state.stage == InstallStage.failed) {
      await installer.refresh();
    }
  }

  Future<void> _acceptBasic() async {
    setState(() => _basicAccepted = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_basicKey, true);
  }

  Future<void> _remove() async {
    final local = _local;
    final model = local?.installer.state.model;
    if (local == null || model == null) return;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sprachmodell entfernen?'),
        content: Text(
          'Dadurch werden ${formatBytes(model.bytes)} frei. Bevor du den Assistenten wieder benutzen kannst, '
          'muss er das Sprachmodell neu laden.',
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: dark ? AppPalette.terracottaDark : AppPalette.terracotta,
              foregroundColor: dark ? AppPalette.canvasDark : Colors.white,
              elevation: 0,
              shape: const StadiumBorder(),
            ),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _modelChat?.clear();
    await local.runtime.unload();
    await local.installer.remove();
  }

  @override
  Widget build(BuildContext context) {
    final local = _local;
    final Widget child;
    if (local == null) {
      child = _ChatView(
        key: const ValueKey('basic'),
        chat: _basicChat,
        mode: kIsWeb ? _ChatMode.web : _ChatMode.basic,
        ready: _engineReady,
      );
    } else {
      final state = local.installer.state;
      if (state.stage == InstallStage.installed) {
        child = _ChatView(
          key: const ValueKey('model'),
          chat: _chatFor(local),
          mode: _ChatMode.model,
          ready: _engineReady,
          onRemove: _remove,
        );
      } else if (state.stage == InstallStage.unsupported && _basicAccepted) {
        child = _ChatView(key: const ValueKey('basic'), chat: _basicChat, mode: _ChatMode.basic, ready: _engineReady);
      } else {
        final canLeave = Navigator.of(context).canPop();
        child = AssistantInstallView(
          key: const ValueKey('gate'),
          state: state,
          onInstall: () => unawaited(_install()),
          onCancel: local.installer.cancel,
          onRetry: () => unawaited(_install(retry: true)),
          onOpen: local.installer.open,
          onBasic: () => unawaited(_acceptBasic()),
          onRemove: () => unawaited(_remove()),
          onLater: canLeave ? () => unawaited(Navigator.of(context).maybePop()) : null,
        );
      }
    }
    return AnimatedSwitcher(
      duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
      child: child,
    );
  }
}

enum _ChatMode { model, basic, web }

class _ChatView extends StatefulWidget {
  const _ChatView({super.key, required this.chat, required this.mode, required this.ready, this.onRemove});

  final AssistantChat chat;
  final _ChatMode mode;
  final bool ready;
  final VoidCallback? onRemove;

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  int _seen = 0;
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    widget.chat.addListener(_chatChanged);
    _seen = widget.chat.entries.length;
  }

  @override
  void didUpdateWidget(covariant _ChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chat != widget.chat) {
      oldWidget.chat.removeListener(_chatChanged);
      widget.chat.addListener(_chatChanged);
    }
  }

  @override
  void dispose() {
    widget.chat.removeListener(_chatChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _chatChanged() {
    if (!mounted) return;
    final grew = widget.chat.entries.length != _seen;
    _seen = widget.chat.entries.length;
    if (grew) _follow = true;
    setState(() {});
    _scrollToEnd(animate: grew);
  }

  bool _scrolled(ScrollNotification notification) {
    if (notification is UserScrollNotification || notification is ScrollEndNotification) {
      final metrics = notification.metrics;
      _follow = metrics.maxScrollExtent - metrics.pixels < 48;
    }
    return false;
  }

  void _send([String? preset]) {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty || widget.chat.busy || !widget.ready) return;
    _controller.clear();
    unawaited(widget.chat.ask(text));
  }

  void _scrollToEnd({bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_follow || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (animate && !MediaQuery.of(context).disableAnimations) {
        _scrollController.animateTo(
          position.maxScrollExtent,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        );
      } else if (position.pixels != position.maxScrollExtent) {
        _scrollController.jumpTo(position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chat = widget.chat;
    final model = widget.mode == _ChatMode.model;
    final subtitle = model
        ? 'Läuft komplett auf deinem Handy. Nur bei Fragen wie „Wer war Goethe?“ schlägt er online bei Wikipedia nach.'
        : 'Rechnen, Formeln, Daten, Literatur-Epochen und bekannte Werke, alles offline. '
            'Für neue Biografien wird Internet verwendet.';

    return PageFadeIn(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
              children: [
                AppTheme.gradientText('Assistent', fontSize: 36),
                const Spacer(),
                _StatusPill(ready: widget.ready, model: model),
                if (widget.onRemove != null)
                  _ChatMenu(
                    onNewChat: chat.entries.isEmpty ? null : chat.clear,
                    onRemove: widget.onRemove!,
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                subtitle,
                style:
                    TextStyle(fontSize: 12, height: 1.4, color: isDark ? AppPalette.inkMutedDark : AppPalette.inkMuted),
              ),
            ),
          ),
          if (widget.mode == _ChatMode.web)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _WebNote(),
            ),
          Expanded(
            child: chat.entries.isEmpty
                ? _EmptyState(model: model, onTap: _send)
                : NotificationListener<ScrollNotification>(
                    onNotification: _scrolled,
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      itemCount:
                          chat.entries.length + (chat.phase == ChatPhase.thinking && !_hasOpenReply(chat) ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == chat.entries.length) return const _TypingBubble();
                        final entry = chat.entries[i];
                        return _Bubble(
                          entry: entry,
                          phase: entry.streaming ? chat.phase : ChatPhase.idle,
                          onRetry: entry.failed && entry.question != null ? () => unawaited(chat.retry(entry)) : null,
                        );
                      },
                    ),
                  ),
          ),
          _InputBar(
            controller: _controller,
            onSubmit: () => _send(),
            onStop: chat.usesModel && chat.busy ? chat.stop : null,
            enabled: widget.ready && !chat.busy,
            maxLength: model ? 2000 : 500,
          ),
        ],
      ),
    );
  }

  static bool _hasOpenReply(AssistantChat chat) => chat.entries.isNotEmpty && chat.entries.last.streaming;
}

class _WebNote extends StatelessWidget {
  const _WebNote();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(
        color: isDark ? AppPalette.sageSoftDark : AppPalette.sageSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.smartphone_rounded, size: 17, color: isDark ? const Color(0xFFAFC798) : AppPalette.sageInk),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Der KI-Assistent mit Sprachmodell läuft in den Apps für Android und iOS.',
              style: TextStyle(fontSize: 13, height: 1.35, color: isDark ? AppPalette.inkDark : AppPalette.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMenu extends StatelessWidget {
  const _ChatMenu({required this.onNewChat, required this.onRemove});

  final VoidCallback? onNewChat;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final urgent = isDark ? AppPalette.terracottaDark : AppPalette.terracottaInk;
    return PopupMenuButton<String>(
      tooltip: 'Mehr',
      icon: const Icon(Icons.more_horiz_rounded),
      position: PopupMenuPosition.under,
      onSelected: (value) {
        if (value == 'new') onNewChat?.call();
        if (value == 'remove') onRemove();
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'new',
          enabled: onNewChat != null,
          child: const Row(
            children: [
              Icon(Icons.add_comment_outlined, size: 20),
              SizedBox(width: 12),
              Text('Neuer Chat'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'remove',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 20, color: urgent),
              const SizedBox(width: 12),
              Text('Sprachmodell entfernen', style: TextStyle(color: urgent)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.entry, required this.phase, this.onRetry});

  final ChatEntry entry;
  final ChatPhase phase;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUser = entry.role == ChatRole.user;
    final ink = isDark ? AppPalette.inkDark : AppPalette.ink;
    final muted = isDark ? AppPalette.inkMutedDark : AppPalette.inkMuted;
    final style = TextStyle(fontSize: 14.5, height: 1.45, color: ink);
    final loading = entry.streaming && entry.text.isEmpty;

    Widget content;
    if (loading && phase == ChatPhase.loadingModel) {
      content = const _ModelLoading();
    } else if (loading) {
      content = const _TypingDots();
    } else {
      content = ChatMarkdown(text: entry.text, style: entry.failed ? style.copyWith(color: muted) : style);
    }

    final label = !isUser && !entry.streaming && !entry.failed ? _sourceLabel(entry) : null;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * (isUser ? .8 : .88)),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
          decoration: BoxDecoration(
            color: isUser
                ? (isDark ? AppPalette.heroDark : AppPalette.sageSoft)
                : (isDark ? AppPalette.surfaceDark : AppPalette.surface),
            border: isUser ? null : Border.all(color: isDark ? AppPalette.lineDark : AppPalette.line),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isUser ? 18 : 6),
              bottomRight: Radius.circular(isUser ? 6 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isUser) Text(entry.text, style: style) else SelectionArea(child: content),
              if (label != null) ...[
                const SizedBox(height: 6),
                Text(label, style: TextStyle(fontSize: 10.5, color: muted.withValues(alpha: .8))),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: const Text('Erneut versuchen'),
                  style: TextButton.styleFrom(
                    foregroundColor: ink,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String? _sourceLabel(ChatEntry entry) {
    if (entry.local) return '• auf dem Gerät · sprachmodell';
    switch (entry.source) {
      case AssistantSource.math:
        return '• offline · rechnen';
      case AssistantSource.date:
        return '• offline · datum';
      case AssistantSource.unit:
        return '• offline · einheiten';
      case AssistantSource.formula:
        return '• offline · formelsammlung';
      case AssistantSource.epoch:
        return '• offline · literaturepochen';
      case AssistantSource.werk:
        return '• offline · werkliste';
      case AssistantSource.topics:
        return '• offline · lehrplan';
      case AssistantSource.cached:
        return '• offline · wikipedia-cache';
      case AssistantSource.wikipedia:
        return '• online · wikipedia';
      case AssistantSource.unknown:
      case null:
        return null;
    }
  }
}

class _ModelLoading extends StatelessWidget {
  const _ModelLoading();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return SizedBox(
      width: 190,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Assistent wird geladen …',
            style: TextStyle(fontSize: 14, color: isDark ? AppPalette.inkSoftDark : AppPalette.inkSoft),
          ),
          if (!reduceMotion) ...[
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 4,
                color: isDark ? AppPalette.sageDark : AppPalette.sage,
                backgroundColor: isDark ? AppPalette.lineDark : AppPalette.line,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
        decoration: BoxDecoration(
          color: isDark ? AppPalette.surfaceDark : AppPalette.surface,
          border: Border.all(color: isDark ? AppPalette.lineDark : AppPalette.line),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(6),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: const _TypingDots(),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? AppPalette.inkMutedDark : AppPalette.inkMuted;
    return SizedBox(
      height: 14,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              Opacity(
                opacity: _dot(i),
                child: Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  double _dot(int index) {
    if (!_controller.isAnimating) return .7;
    final t = (_controller.value - index * .18) % 1.0;
    final wave = t < .5 ? t * 2 : (1 - t) * 2;
    return .3 + .7 * Curves.easeInOut.transform(wave.clamp(0.0, 1.0));
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.onSubmit,
    required this.onStop,
    required this.enabled,
    required this.maxLength,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final VoidCallback? onStop;
  final bool enabled;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brand = isDark ? AppPalette.brandDark : AppPalette.pine;
    final onBrand = isDark ? AppPalette.inkDark : AppPalette.chalk;
    final stop = onStop;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => onSubmit(),
                inputFormatters: [LengthLimitingTextInputFormatter(maxLength)],
                decoration: InputDecoration(
                  hintText: enabled || stop != null ? 'Frage stellen …' : 'Bereit in einem Moment …',
                  filled: true,
                  fillColor: isDark ? AppPalette.surfaceDark : AppPalette.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: isDark ? AppPalette.lineDark : AppPalette.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: isDark ? AppPalette.lineDark : AppPalette.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: isDark ? AppPalette.inkMutedDark : AppPalette.inkSoft, width: 1.4),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: Tween(begin: .85, end: 1.0).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: stop != null
                  ? IconButton.filled(
                      key: const ValueKey('stop'),
                      tooltip: 'Stopp',
                      onPressed: stop,
                      icon: const Icon(Icons.stop_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: brand,
                        foregroundColor: onBrand,
                        minimumSize: const Size(48, 48),
                      ),
                    )
                  : IconButton.filled(
                      key: const ValueKey('send'),
                      tooltip: 'Senden',
                      onPressed: enabled ? onSubmit : null,
                      icon: const Icon(Icons.arrow_upward_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: brand,
                        foregroundColor: onBrand,
                        disabledBackgroundColor: brand.withValues(alpha: .3),
                        disabledForegroundColor: onBrand.withValues(alpha: .7),
                        minimumSize: const Size(48, 48),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.ready, required this.model});

  final bool ready;
  final bool model;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sage = isDark ? AppPalette.sageDark : AppPalette.sage;
    final muted = isDark ? AppPalette.inkMutedDark : AppPalette.inkMuted;
    final label = !ready ? 'lädt …' : (model ? 'auf dem Gerät' : 'offline');
    final icon = !ready ? Icons.hourglass_empty_rounded : (model ? Icons.smartphone_rounded : Icons.wifi_off_rounded);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: ready ? sage.withValues(alpha: .13) : muted.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: ready ? sage : muted),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ready ? sage : muted),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.model, required this.onTap});

  final bool model;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final suggestions = model
        ? const [
            'Was steht diese Woche an?',
            'Hilf mir, für die nächste Klausur zu lernen',
            'Erklär mir, wie ein Elektromotor funktioniert',
            'Formulier eine kurze Mail an meine Lehrerin',
            '15% von 200',
            'Ableitung von sin(x)',
          ]
        : const [
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
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      children: [
        GlassCard(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          borderRadius: 20,
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isDark ? AppPalette.sageSoftDark : AppPalette.sageSoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  model ? Icons.forum_outlined : Icons.calculate_outlined,
                  size: 24,
                  color: isDark ? const Color(0xFFAFC798) : AppPalette.sageInk,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Frag mich was',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: isDark ? AppPalette.inkDark : AppPalette.ink),
              ),
              const SizedBox(height: 6),
              Text(
                model
                    ? 'Zum Beispiel zu deinem Stundenplan, zu Hausaufgaben oder zu einem Thema, das du gerade lernst.'
                    : 'Rechnen, Formeln, Daten, Literatur und Lehrplan, alles offline.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 13, height: 1.4, color: isDark ? AppPalette.inkMutedDark : AppPalette.inkMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Probier zum Beispiel:',
          style: TextStyle(fontSize: 13, color: isDark ? AppPalette.inkMutedDark : AppPalette.inkMuted),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final suggestion in suggestions)
              ActionChip(
                label: Text(suggestion, style: const TextStyle(fontSize: 12.5)),
                onPressed: () => onTap(suggestion),
              ),
          ],
        ),
      ],
    );
  }
}
