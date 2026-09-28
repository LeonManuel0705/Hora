// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';

import '../brand.dart';
import '../services/assistant/local_model/model_format.dart';
import '../services/assistant/local_model/model_installer.dart';
import '../services/assistant/local_model/model_manifest.dart';
import '../theme.dart';

class AssistantInstallView extends StatelessWidget {
  const AssistantInstallView({
    super.key,
    required this.state,
    required this.onInstall,
    required this.onCancel,
    required this.onRetry,
    required this.onOpen,
    required this.onBasic,
    this.onRemove,
    this.onLater,
  });

  final InstallState state;
  final VoidCallback onInstall;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onOpen;
  final VoidCallback onBasic;
  final VoidCallback? onRemove;
  final VoidCallback? onLater;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final key = ValueKey('${state.stage.name}-${state.problem?.name}-${state.unsupported?.name}');
    final page = switch (state.stage) {
      InstallStage.checking => const SizedBox.expand(),
      InstallStage.unsupported => _unsupported(context),
      InstallStage.offer => _offer(context),
      InstallStage.downloading || InstallStage.starting => _progress(context),
      InstallStage.ready => _ready(context),
      InstallStage.failed => _failed(context),
      InstallStage.installed => const SizedBox.expand(),
    };
    final group = switch (state.stage) {
      InstallStage.downloading || InstallStage.starting => const ValueKey('progress'),
      _ => key,
    };
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, .02), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: group, child: page),
    );
  }

  Widget _offer(BuildContext context) {
    final colors = _GateColors.of(context);
    final model = state.model!;
    final partial = state.partialBytes > 0 && state.partialBytes < model.bytes;
    final free = state.freeBytes;
    return _GateLayout(
      content: [
        const _Emblem(icon: Icons.download_rounded, tone: _Tone.brand),
        const SizedBox(height: 22),
        const _Title('Assistent installieren'),
        const SizedBox(height: 10),
        const _Body(
          'Der Assistent läuft komplett auf deinem Handy. Dafür lädt ${Brand.name} einmalig ein Sprachmodell '
          'herunter, danach funktioniert er auch ohne Internet.',
        ),
        const SizedBox(height: 24),
        _Card(
          children: [
            _Fact(icon: Icons.downloading_rounded, title: formatBytes(model.bytes), caption: 'einmaliger Download'),
            const _Fact(
              icon: Icons.lock_outline_rounded,
              title: 'Deine Fragen verlassen das Gerät nicht.',
              caption: 'Alles wird auf dem Handy berechnet.',
            ),
            if (free != null)
              _Fact(
                icon: Icons.sd_storage_outlined,
                title: 'Frei: ${formatBytes(free)}',
                caption: free > model.bytes - state.partialBytes
                    ? 'Danach sind noch etwa ${formatBytes(free - (model.bytes - state.partialBytes))} frei.'
                    : 'Das reicht noch nicht für das Sprachmodell.',
                captionColor: free > model.bytes - state.partialBytes ? null : colors.urgent,
              ),
          ],
        ),
        if (state.onMobileData) ...[
          const SizedBox(height: 12),
          const _Note(
            icon: Icons.signal_cellular_alt_rounded,
            text: 'Du bist gerade im Mobilfunknetz. Am besten lädst du im WLAN.',
            tone: _Tone.sand,
          ),
        ],
        if (partial) ...[
          const SizedBox(height: 12),
          _Note(
            icon: Icons.history_rounded,
            text: 'Schon geladen: ${formatAmount(state.partialBytes, model.bytes)}. Der Download macht dort weiter.',
            tone: _Tone.sage,
          ),
        ],
      ],
      actions: [
        _PrimaryButton(label: partial ? 'Fortsetzen' : 'Installieren', icon: Icons.download_rounded, onPressed: onInstall),
        if (onLater != null) _LaterButton(onPressed: onLater!),
      ],
    );
  }

  Widget _progress(BuildContext context) {
    final starting = state.stage == InstallStage.starting;
    final model = state.model!;
    final progress = state.progress;
    final checking = progress?.checking ?? false;
    final fraction = starting ? 1.0 : (progress?.fraction ?? 0);
    final line = starting
        ? 'Das Sprachmodell startet zum ersten Mal.'
        : progress == null
            ? formatAmount(state.partialBytes, model.bytes)
            : formatProgress(progress);
    return _GateLayout(
      content: [
        const _Emblem(icon: Icons.downloading_rounded, tone: _Tone.sage),
        const SizedBox(height: 22),
        const _Title('Assistent wird installiert'),
        const SizedBox(height: 22),
        _ProgressCard(fraction: fraction, line: line, caption: checking ? 'Bereits geladene Teile werden geprüft …' : null),
        const SizedBox(height: 12),
        _Steps(
          current: starting ? 2 : 0,
          labels: const ['Sprachmodell laden', 'Prüfen', 'Starten'],
        ),
        if (state.secondAttempt && !starting) ...[
          const SizedBox(height: 12),
          const _Note(
            icon: Icons.replay_rounded,
            text: 'Die erste Datei kam beschädigt an. ${Brand.name} lädt sie noch einmal.',
            tone: _Tone.sand,
          ),
        ],
        const SizedBox(height: 12),
        const _Note(
          icon: Icons.info_outline_rounded,
          text: 'Lass ${Brand.name} geöffnet, bis alles fertig ist. Du kannst die App solange normal benutzen. '
              'Wenn du sie zwischendurch verlässt, geht es weiter, sobald du zurückkommst.',
          tone: _Tone.quiet,
        ),
      ],
      actions: [
        if (!starting) _OutlineButton(label: 'Abbrechen', onPressed: onCancel),
      ],
    );
  }

  Widget _ready(BuildContext context) {
    return _GateLayout(
      content: const [
        _Emblem(icon: Icons.check_rounded, tone: _Tone.sage),
        SizedBox(height: 22),
        _Title('Fertig. Der Assistent ist\u00a0bereit.'),
        SizedBox(height: 10),
        _Body('Er läuft jetzt auf deinem Handy und braucht kein Internet mehr.'),
      ],
      actions: [
        _PrimaryButton(label: 'Assistent öffnen', icon: Icons.arrow_forward_rounded, onPressed: onOpen),
      ],
    );
  }

  Widget _failed(BuildContext context) {
    final model = state.model;
    final (icon, title, body) = switch (state.problem) {
      InstallProblem.offline => (
          Icons.wifi_off_rounded,
          'Keine Verbindung',
          'Prüf dein Internet und versuch es noch einmal. Bereits geladene Teile bleiben erhalten.',
        ),
      InstallProblem.storage => (
          Icons.sd_storage_outlined,
          'Nicht genug Speicherplatz',
          'Es fehlen noch ${formatMissing(state.missingBytes)}. Mach etwas Platz frei, zum Beispiel bei Fotos, '
              'Videos oder alten Apps, und versuch es dann noch einmal.',
        ),
      InstallProblem.checksum => (
          Icons.report_gmailerrorred_rounded,
          'Datei beschädigt',
          'Die Datei kam beschädigt an, auch beim zweiten Versuch. Versuch es später noch einmal, am besten in '
              'einem anderen WLAN.',
        ),
      InstallProblem.loadFailed => (
          Icons.memory_rounded,
          'Der Assistent startet nicht',
          'Das Sprachmodell ist heruntergeladen, ließ sich aber nicht starten. Schließ andere Apps und versuch es noch einmal.',
        ),
      _ => (
          Icons.cloud_off_rounded,
          'Download gerade nicht möglich',
          'Der Server hat nicht wie erwartet geantwortet. Versuch es später noch einmal. '
              'Bereits geladene Teile bleiben erhalten.',
        ),
    };
    final keeps = state.partialBytes > 0 &&
        model != null &&
        (state.problem == InstallProblem.offline || state.problem == InstallProblem.server);
    return _GateLayout(
      content: [
        _Emblem(icon: icon, tone: _Tone.warn),
        const SizedBox(height: 22),
        _Title(title),
        const SizedBox(height: 10),
        _Body(body),
        if (keeps) ...[
          const SizedBox(height: 18),
          _Note(
            icon: Icons.history_rounded,
            text: 'Schon geladen: ${formatAmount(state.partialBytes, model.bytes)}.',
            tone: _Tone.sage,
          ),
        ],
      ],
      actions: [
        _PrimaryButton(label: 'Erneut versuchen', icon: Icons.refresh_rounded, onPressed: onRetry),
        if (state.problem == InstallProblem.loadFailed && onRemove != null)
          _QuietButton(label: 'Sprachmodell entfernen', onPressed: onRemove!)
        else if (onLater != null)
          _LaterButton(onPressed: onLater!),
      ],
    );
  }

  Widget _unsupported(BuildContext context) {
    final body = switch (state.unsupported) {
      ModelUnsupportedReason.memory => state.totalMemory == null
          ? 'Das Sprachmodell braucht mindestens 6 GB Arbeitsspeicher, damit es flüssig läuft. '
              'Dein Handy hat weniger.'
          : 'Das Sprachmodell braucht mindestens 6 GB Arbeitsspeicher, damit es flüssig läuft. '
              'Dein Handy hat ${(state.totalMemory! / 1e9).round()} GB.',
      ModelUnsupportedReason.architecture =>
        'Das Sprachmodell braucht einen Prozessor mit 64\u00a0Bit, dein Handy arbeitet mit 32\u00a0Bit.',
      _ => 'Auf diesem Gerät kann ${Brand.name} das Sprachmodell nicht einrichten.',
    };
    return _GateLayout(
      content: [
        const _Emblem(icon: Icons.mobile_off_rounded, tone: _Tone.quiet),
        const SizedBox(height: 22),
        const _Title('Auf diesem Handy nicht\u00a0verfügbar'),
        const SizedBox(height: 10),
        _Body(body),
        const SizedBox(height: 18),
        const _Note(
          icon: Icons.calculate_outlined,
          text: 'Rechnen, Formeln, Daten und Fragen zum Lehrplan beantwortet der Assistent trotzdem, ganz ohne Sprachmodell.',
          tone: _Tone.sage,
        ),
      ],
      actions: [
        _PrimaryButton(label: 'Einfachen Assistenten öffnen', icon: Icons.arrow_forward_rounded, onPressed: onBasic),
        if (onLater != null) _LaterButton(onPressed: onLater!),
      ],
    );
  }
}

Future<bool> confirmMobileDownload(BuildContext context, int bytes) async {
  final colors = _GateColors.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Über Mobilfunk laden?'),
      content: Text(
        'Das Sprachmodell ist ${formatBytes(bytes)} groß. Über Mobilfunk geht das von deinem Datenvolumen ab, '
        'im WLAN nicht.',
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: colors.primaryButton(compact: true),
          child: const Text('Trotzdem laden'),
        ),
      ],
    ),
  );
  return result ?? false;
}

class _GateColors {
  const _GateColors(this.dark);

  factory _GateColors.of(BuildContext context) => _GateColors(Theme.of(context).brightness == Brightness.dark);

  final bool dark;

  Color get ink => dark ? AppPalette.inkDark : AppPalette.ink;
  Color get soft => dark ? AppPalette.inkSoftDark : AppPalette.inkSoft;
  Color get muted => dark ? AppPalette.inkMutedDark : AppPalette.inkMuted;
  Color get line => dark ? AppPalette.lineDark : AppPalette.line;
  Color get surface => dark ? AppPalette.surfaceDark : AppPalette.surface;
  Color get sunken => dark ? AppPalette.hoverDark : AppPalette.sunken;
  Color get sage => dark ? AppPalette.sageDark : AppPalette.sage;
  Color get urgent => dark ? AppPalette.terracottaDark : AppPalette.terracottaInk;

  ButtonStyle primaryButton({bool compact = false}) => ElevatedButton.styleFrom(
        backgroundColor: dark ? AppPalette.brandDark : AppPalette.pine,
        foregroundColor: dark ? AppPalette.inkDark : AppPalette.chalk,
        elevation: 0,
        shadowColor: Colors.transparent,
        padding: EdgeInsets.symmetric(horizontal: 22, vertical: compact ? 12 : 16),
        shape: StadiumBorder(side: dark ? const BorderSide(color: Color(0xFF3E5541)) : BorderSide.none),
        textStyle: const TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 16, fontWeight: FontWeight.w600),
      );
}

enum _Tone { brand, sage, warn, quiet, sand }

class _GateLayout extends StatelessWidget {
  const _GateLayout({required this.content, required this.actions});

  final List<Widget> content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: content),
              ),
            ),
            if (actions.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 16 + bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(height: 6),
                      actions[i],
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Emblem extends StatelessWidget {
  const _Emblem({required this.icon, required this.tone});

  final IconData icon;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (background, foreground) = switch (tone) {
      _Tone.brand => (dark ? AppPalette.heroDark : AppPalette.pine, dark ? AppPalette.inkDark : AppPalette.chalk),
      _Tone.sage => (dark ? AppPalette.sageSoftDark : AppPalette.sageSoft, dark ? const Color(0xFFAFC798) : AppPalette.sageInk),
      _Tone.warn => (
          dark ? AppPalette.terracottaSoftDark : AppPalette.terracottaSoft,
          dark ? AppPalette.terracottaDark : AppPalette.terracottaInk,
        ),
      _Tone.sand => (dark ? const Color(0xFF3A3122) : AppPalette.amberSoft, dark ? AppPalette.sand : AppPalette.ochre),
      _Tone.quiet => (dark ? AppPalette.hoverDark : AppPalette.sunken, dark ? AppPalette.inkMutedDark : AppPalette.inkMuted),
    };
    final emblem = Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
      child: Icon(icon, color: foreground, size: 30),
    );
    if (MediaQuery.of(context).disableAnimations) return emblem;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.scale(scale: .9 + .1 * value, alignment: Alignment.bottomLeft, child: child),
      ),
      child: emblem,
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: 28,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -.5,
        color: _GateColors.of(context).ink,
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: TextStyle(fontSize: 16, height: 1.45, color: _GateColors.of(context).soft));
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = _GateColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, indent: 64, color: colors.line),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.title, required this.caption, this.captionColor});

  final IconData icon;
  final String title;
  final String caption;
  final Color? captionColor;

  @override
  Widget build(BuildContext context) {
    final colors = _GateColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: colors.sunken, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 19, color: colors.soft),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: colors.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(caption, style: TextStyle(fontSize: 13, height: 1.35, color: captionColor ?? colors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, required this.tone});

  final IconData icon;
  final String text;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final colors = _GateColors.of(context);
    final (background, foreground) = switch (tone) {
      _Tone.sand => (dark ? const Color(0xFF2E281C) : AppPalette.amberSoft, dark ? AppPalette.sand : AppPalette.ochre),
      _Tone.sage => (dark ? AppPalette.sageSoftDark : AppPalette.sageSoft, dark ? const Color(0xFFAFC798) : AppPalette.sageInk),
      _Tone.warn => (
          dark ? AppPalette.terracottaSoftDark : AppPalette.terracottaSoft,
          dark ? AppPalette.terracottaDark : AppPalette.terracottaInk,
        ),
      _ => (colors.sunken, colors.muted),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 18, color: foreground)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, height: 1.4, color: tone == _Tone.quiet ? colors.soft : colors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.fraction, required this.line, this.caption});

  final double fraction;
  final String line;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final colors = _GateColors.of(context);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.line),
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: fraction),
        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${(value * 100).floor()} %',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 34,
                height: 1.1,
                fontWeight: FontWeight.w700,
                letterSpacing: -.6,
                color: colors.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 10,
                child: Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: colors.sunken)),
                    FractionallySizedBox(
                      widthFactor: value.clamp(0.0, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: colors.sage, borderRadius: BorderRadius.circular(99)),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              caption ?? line,
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: colors.soft,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.current, required this.labels});

  final int current;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final colors = _GateColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  _StepMark(done: i < current, active: i == current),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: i == current ? FontWeight.w600 : FontWeight.w500,
                        color: i > current ? colors.muted : colors.ink,
                      ),
                    ),
                  ),
                  if (i < current) Text('erledigt', style: TextStyle(fontSize: 13, color: colors.muted)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StepMark extends StatelessWidget {
  const _StepMark({required this.done, required this.active});

  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = _GateColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 240),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? colors.sage : Colors.transparent,
        border: Border.all(color: done ? colors.sage : (active ? colors.ink : colors.line), width: 2),
      ),
      child: done
          ? Icon(Icons.check_rounded, size: 14, color: dark ? AppPalette.canvasDark : Colors.white)
          : active
              ? Center(
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: colors.ink),
                  ),
                )
              : null,
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.icon, required this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      label: Text(label),
      style: _GateColors.of(context).primaryButton(),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = _GateColors.of(context);
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.ink,
        padding: const EdgeInsets.symmetric(vertical: 16),
        side: BorderSide(color: Theme.of(context).brightness == Brightness.dark ? AppPalette.lineStrongDark : AppPalette.lineStrong),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 16, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}

class _LaterButton extends StatelessWidget {
  const _LaterButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => _QuietButton(label: 'Nicht jetzt', onPressed: onPressed);
}

class _QuietButton extends StatelessWidget {
  const _QuietButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: _GateColors.of(context).muted,
        padding: const EdgeInsets.symmetric(vertical: 14),
        textStyle: const TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 15, fontWeight: FontWeight.w500),
      ),
      child: Text(label),
    );
  }
}
