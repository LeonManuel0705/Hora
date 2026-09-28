// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'model_downloader.dart';

const _space = '\u00a0';

String _decimal(double value, int digits) => value.toStringAsFixed(digits).replaceAll('.', ',');

String formatBytes(int bytes) {
  if (bytes < 0) bytes = 0;
  final gigabytes = bytes / 1e9;
  if (gigabytes >= 10) return '${gigabytes.round()}${_space}GB';
  if (gigabytes >= 1) return '${_decimal(gigabytes, 1)}${_space}GB';
  final megabytes = bytes / 1e6;
  if (megabytes >= 1) return '${megabytes.round()}${_space}MB';
  return '${(bytes / 1e3).ceil()}${_space}KB';
}

String formatMissing(int bytes) {
  final gigabytes = bytes / 1e9;
  if (gigabytes >= 10) return '${gigabytes.ceil()}${_space}GB';
  if (gigabytes >= 0.1) return '${_decimal((gigabytes * 10).ceil() / 10, 1)}${_space}GB';
  return '${((bytes / 1e6).ceil()).clamp(1, 100)}${_space}MB';
}

String formatSpeed(double bytesPerSecond) {
  final megabytes = bytesPerSecond / 1e6;
  if (megabytes >= 100) return '${megabytes.round()}${_space}MB/s';
  if (megabytes >= 0.1) return '${_decimal(megabytes, 1)}${_space}MB/s';
  return '${(bytesPerSecond / 1e3).round()}${_space}KB/s';
}

String formatRemaining(Duration remaining) {
  final minutes = (remaining.inSeconds / 60).ceil();
  if (remaining.inSeconds < 60) return 'noch weniger als 1${_space}Min.';
  if (minutes < 60) return 'noch etwa $minutes${_space}Min.';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? 'noch etwa $hours${_space}Std.' : 'noch etwa $hours${_space}Std. $rest${_space}Min.';
}

String formatAmount(int received, int total) {
  final gigabytes = total / 1e9;
  if (gigabytes >= 1) {
    final digits = gigabytes >= 10 ? 0 : 1;
    return '${_decimal(received / 1e9, digits)} von ${_decimal(gigabytes, digits)}${_space}GB';
  }
  return '${(received / 1e6).round()} von ${(total / 1e6).round()}${_space}MB';
}

String formatProgress(DownloadProgress progress) {
  final parts = [formatAmount(progress.received, progress.total)];
  if (!progress.checking && progress.bytesPerSecond >= 1) {
    parts.add(formatSpeed(progress.bytesPerSecond));
    final remaining = progress.remaining;
    if (remaining != null) parts.add(formatRemaining(remaining));
  }
  return parts.join(' · ');
}
