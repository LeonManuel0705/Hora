# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import os
import threading

from . import brand
from datetime import datetime
from typing import Optional

LOGS_DIR = os.path.join(os.path.dirname(__file__), 'logs')

_log_file = None
_log_lock = threading.Lock()
_logging_enabled = False
_session_id = None

def init_logging(enabled: bool = False):
    global _logging_enabled, _log_file, _session_id

    _logging_enabled = enabled

    if not enabled:
        return

    if not os.path.exists(LOGS_DIR):
        os.makedirs(LOGS_DIR)

    _session_id = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_filename = f"session_{_session_id}.txt"
    _log_file = os.path.join(LOGS_DIR, log_filename)

    with open(_log_file, 'w') as f:
        f.write(f"{brand.NAME} Session Log\n")
        f.write(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write("=" * 50 + "\n\n")

def is_logging_enabled() -> bool:
    return _logging_enabled

def log(category: str, message: str, data: Optional[dict] = None):
    if not _logging_enabled or not _log_file:
        return

    with _log_lock:
        try:
            timestamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]
            log_entry = f"[{timestamp}] [{category}] {message}"

            if data:
                for key, value in data.items():
                    log_entry += f"\n    {key}: {value}"

            log_entry += "\n"

            with open(_log_file, 'a') as f:
                f.write(log_entry)
        except Exception as e:
            print(f"Logging error: {e}")

def log_voice_filter(profile_name: str, match_result: bool, confidence: float):
    log("VOICE_FILTER", f"Profile: {profile_name}", {
        "match": match_result,
        "confidence": f"{confidence:.2f}"
    })

def log_transcription(raw_text: str, corrected_text: str, language: str):
    log("TRANSCRIPTION", "Segment processed", {
        "language": language,
        "raw_length": len(raw_text),
        "corrected_length": len(corrected_text),
        "raw": raw_text[:100] + "..." if len(raw_text) > 100 else raw_text
    })

def log_recording_start(device: str, language: str):
    log("RECORDING", "Started", {
        "device": device,
        "language": language
    })

def log_recording_stop(duration: float, segments_count: int):
    log("RECORDING", "Stopped", {
        "duration_seconds": f"{duration:.1f}",
        "segments": segments_count
    })

def log_error(category: str, error: str):
    log("ERROR", f"{category}: {error}")

def log_correction(original: str, corrected: str, method: str):
    log("CORRECTION", f"Applied via {method}", {
        "original_length": len(original),
        "corrected_length": len(corrected)
    })

def close_logging():
    global _log_file

    if _logging_enabled and _log_file:
        with _log_lock:
            try:
                with open(_log_file, 'a') as f:
                    f.write("\n" + "=" * 50 + "\n")
                    f.write(f"Session ended: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            except Exception:
                pass

    _log_file = None
