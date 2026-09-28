// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';

class ChatMarkdown extends StatelessWidget {
  const ChatMarkdown({super.key, required this.text, required this.style});

  final String text;
  final TextStyle style;

  static final _heading = RegExp(r'^\s{0,3}#{1,6}\s+(.*)$');
  static final _bullet = RegExp(r'^(\s*)[-*•+]\s+(.*)$');
  static final _numbered = RegExp(r'^(\s*)(\d{1,3})[.)]\s+(.*)$');
  static final _inline = RegExp(r'\*\*(.+?)\*\*|__(.+?)__|`([^`]+)`|(?<![\w*])\*(?!\s)([^*\n]+?)\*(?![\w*])');

  @override
  Widget build(BuildContext context) {
    final blocks = <Widget>[];
    final paragraph = <String>[];

    void flush() {
      if (paragraph.isEmpty) return;
      blocks.add(Text.rich(_spans(paragraph.join('\n'), style)));
      paragraph.clear();
    }

    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        flush();
        continue;
      }
      final heading = _heading.firstMatch(line);
      if (heading != null) {
        flush();
        blocks.add(Text.rich(_spans(heading[1]!, style.copyWith(fontWeight: FontWeight.w700, fontSize: (style.fontSize ?? 14) + 1))));
        continue;
      }
      final bullet = _bullet.firstMatch(line);
      final numbered = bullet == null ? _numbered.firstMatch(line) : null;
      if (bullet != null || numbered != null) {
        flush();
        final indent = (bullet?[1] ?? numbered![1]!).length >= 2 ? 16.0 : 0.0;
        final marker = bullet != null ? '•' : '${numbered![2]}.';
        final body = bullet?[2] ?? numbered![3]!;
        blocks.add(Padding(
          padding: EdgeInsets.only(left: indent),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: bullet != null ? 14 : 20, child: Text(marker, style: style.copyWith(fontWeight: FontWeight.w600))),
              Expanded(child: Text.rich(_spans(body, style))),
            ],
          ),
        ));
        continue;
      }
      paragraph.add(line);
    }
    flush();

    if (blocks.isEmpty) return Text('', style: style);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < blocks.length; i++)
          Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 6), child: blocks[i]),
      ],
    );
  }

  static TextSpan _spans(String text, TextStyle base) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in _inline.allMatches(text)) {
      if (match.start > last) spans.add(TextSpan(text: text.substring(last, match.start)));
      if (match[1] != null || match[2] != null) {
        spans.add(TextSpan(text: match[1] ?? match[2], style: const TextStyle(fontWeight: FontWeight.w700)));
      } else if (match[3] != null) {
        spans.add(TextSpan(
          text: match[3],
          style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: (base.fontSize ?? 14) - 1),
        ));
      } else {
        spans.add(TextSpan(text: match[4], style: const TextStyle(fontStyle: FontStyle.italic)));
      }
      last = match.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return TextSpan(style: base, children: spans);
  }
}
