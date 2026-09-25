# SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
# SPDX-License-Identifier: AGPL-3.0-only

import os
import sys
import json
import time
import subprocess
import argparse
import signal
from datetime import datetime, timedelta
from pathlib import Path
import logging

sys.path.insert(0, str(Path(__file__).parent))
from app.crypto_utils import encrypt_file, decrypt_file
from app.brand import NAME as BRAND_NAME

LOG_FILE = Path(__file__).parent / 'data' / 'calendar_sync.log'
LOG_FILE.parent.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

SYNC_INTERVAL = 300
CALENDAR_DATA_FILE = Path(__file__).parent / 'data' / 'synced_calendar.json'
PID_FILE = Path(__file__).parent / 'data' / 'calendar_sync.pid'

class MacOSCalendarSync:

    def __init__(self):
        self.events = []
        self.last_sync = None

    def get_calendar_events_eventkit(self, days_ahead=60):


        events = []

        jxa_script = f'''
        ObjC.import('EventKit');
        ObjC.import('Foundation');

        var store = $.EKEventStore.alloc.init;

        // Request access (will use existing permission)
        var calendars = store.calendarsForEntityType($.EKEntityTypeEvent);

        if (calendars.count === 0) {{
            JSON.stringify({{error: "No calendars found"}});
        }}

        // Calculate date range
        var now = $.NSDate.date;
        var calendar = $.NSCalendar.currentCalendar;
        var components = $.NSDateComponents.alloc.init;
        components.day = {days_ahead};
        var endDate = calendar.dateByAddingComponentsToDateOptions(components, now, 0);

        // Create predicate for events
        var predicate = store.predicateForEventsWithStartDateEndDateCalendars(now, endDate, calendars);
        var ekEvents = store.eventsMatchingPredicate(predicate);

        var result = [];
        for (var i = 0; i < ekEvents.count; i++) {{
            var event = ekEvents.objectAtIndex(i);
            var startDate = event.startDate;
            var endDate = event.endDate;

            // Format dates
            var formatter = $.NSDateFormatter.alloc.init;
            formatter.dateFormat = "yyyy-MM-dd HH:mm";

            var startStr = ObjC.unwrap(formatter.stringFromDate(startDate));
            var endStr = ObjC.unwrap(formatter.stringFromDate(endDate));

            result.push({{
                title: ObjC.unwrap(event.title) || "Untitled",
                start: startStr,
                end: endStr,
                location: ObjC.unwrap(event.location) || "",
                notes: ObjC.unwrap(event.notes) || "",
                all_day: event.allDay ? true : false,
                calendar: ObjC.unwrap(event.calendar.title) || ""
            }});
        }}

        JSON.stringify(result);
        '''

        try:
            result = subprocess.run(
                ['osascript', '-l', 'JavaScript', '-e', jxa_script],
                capture_output=True,
                text=True,
                timeout=30
            )

            if result.returncode == 0 and result.stdout.strip():
                data = json.loads(result.stdout.strip())
                if isinstance(data, dict) and 'error' in data:
                    logger.warning(f"EventKit error: {data['error']}")
                    return []

                for evt in data:
                    events.append({
                        'title': evt.get('title', 'Untitled'),
                        'start': evt.get('start', ''),
                        'end': evt.get('end', ''),
                        'location': evt.get('location', ''),
                        'notes': evt.get('notes', ''),
                        'all_day': evt.get('all_day', False),
                        'calendar': evt.get('calendar', ''),
                        'source': 'EventKit'
                    })

            logger.info(f"Retrieved {len(events)} events via EventKit")

        except subprocess.TimeoutExpired:
            logger.error("EventKit JXA timed out")
        except json.JSONDecodeError as e:
            logger.error(f"EventKit JSON parse error: {e}")
        except Exception as e:
            logger.error(f"EventKit error: {e}")

        return events

    def get_calendar_events_icalbuddy(self, days_ahead=60):


        events = []

        try:

            result = subprocess.run(['which', 'icalBuddy'], capture_output=True, text=True)
            if result.returncode != 0:
                logger.warning("icalBuddy not installed. Install with: brew install ical-buddy")
                return self.get_calendar_events_applescript(days_ahead)

            end_date = datetime.now() + timedelta(days=days_ahead)

            cmd = [
                'icalBuddy',
                '-f',
                '-nc',
                '-nrd',
                '-ea',
                '-b', '|||EVENT|||',
                '-df', '%Y-%m-%d',
                '-tf', '%H:%M',
                '-po', 'datetime,title,location,notes',
                '-ps', '|',
                '-eep', 'url,attendees',
                f'eventsFrom:today to:{end_date.strftime("%Y-%m-%d")}'
            ]

            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)

            if result.returncode == 0 and result.stdout:

                lines = result.stdout.strip().split('|||EVENT|||')
                for line in lines:
                    line = line.strip()
                    if not line:
                        continue

                    parts = line.split('|')
                    if len(parts) >= 2:
                        datetime_str = parts[0].strip() if len(parts) > 0 else ''
                        title = parts[1].strip() if len(parts) > 1 else 'Untitled'
                        location = parts[2].strip() if len(parts) > 2 else ''
                        notes = parts[3].strip() if len(parts) > 3 else ''

                        event_start = None
                        event_end = None
                        all_day = False

                        if datetime_str:

                            try:
                                if ' - ' in datetime_str:

                                    date_parts = datetime_str.split(' - ')
                                    start_str = date_parts[0].strip()
                                    end_str = date_parts[1].strip()

                                    if len(start_str) == 10:
                                        all_day = True
                                        event_start = start_str
                                    else:
                                        event_start = start_str

                                        if len(end_str) == 5:
                                            event_end = start_str[:10] + ' ' + end_str
                                        else:
                                            event_end = end_str
                                elif len(datetime_str) == 10:
                                    all_day = True
                                    event_start = datetime_str
                                else:
                                    event_start = datetime_str
                            except Exception as e:
                                logger.debug(f"Date parse error: {e}")
                                event_start = datetime_str

                        events.append({
                            'title': title,
                            'start': event_start,
                            'end': event_end,
                            'location': location,
                            'notes': notes,
                            'all_day': all_day,
                            'source': 'icalBuddy'
                        })

            logger.info(f"Retrieved {len(events)} events via icalBuddy")

        except subprocess.TimeoutExpired:
            logger.error("icalBuddy timed out")
        except Exception as e:
            logger.error(f"icalBuddy error: {e}")
            return self.get_calendar_events_applescript(days_ahead)

        return events

    def get_calendar_events_applescript(self, days_ahead=60):

        events = []

        applescript = f'''
        tell application "Calendar"
            set startDate to current date
            set endDate to startDate + ({days_ahead} * days)
            set output to ""

            repeat with cal in calendars
                set calName to name of cal
                -- Skip subscribed holiday calendars to speed up
                if calName does not contain "Feiertage" and calName does not contain "Holidays" and calName does not contain "Geburtstage" and calName does not contain "Birthdays" then
                    try
                        set calEvents to (every event of cal whose start date >= startDate and start date <= endDate)
                        repeat with evt in calEvents
                            set evtTitle to summary of evt
                            set evtStart to start date of evt
                            set evtEnd to end date of evt
                            set evtAllDay to allday event of evt
                            set evtLocation to ""
                            try
                                set evtLocation to location of evt
                            on error
                                set evtLocation to ""
                            end try

                            -- Format: title|start|end|location|allday|calendar
                            set output to output & evtTitle & "||" & (evtStart as string) & "||" & (evtEnd as string) & "||" & evtLocation & "||" & evtAllDay & "||" & calName & "<<<EVENT>>>"
                        end repeat
                    end try
                end if
            end repeat

            return output
        end tell
        '''

        try:
            result = subprocess.run(
                ['osascript', '-e', applescript],
                capture_output=True,
                text=True,
                timeout=180
            )

            if result.returncode == 0 and result.stdout:
                event_strings = result.stdout.strip().split('<<<EVENT>>>')
                for evt_str in event_strings:
                    evt_str = evt_str.strip()
                    if not evt_str or evt_str == '':
                        continue

                    parts = evt_str.split('||')
                    if len(parts) >= 5:
                        title = parts[0] if parts[0] else 'Untitled'
                        start = parts[1] if len(parts) > 1 else ''
                        end = parts[2] if len(parts) > 2 else ''
                        location = parts[3] if len(parts) > 3 else ''
                        all_day = parts[4].lower() == 'true' if len(parts) > 4 else False
                        calendar = parts[5] if len(parts) > 5 else ''

                        events.append({
                            'title': title,
                            'start': start,
                            'end': end,
                            'location': location,
                            'notes': '',
                            'all_day': all_day,
                            'calendar': calendar,
                            'source': 'AppleScript'
                        })

            logger.info(f"Retrieved {len(events)} events via AppleScript")

        except subprocess.TimeoutExpired:
            logger.error("AppleScript timed out")
        except Exception as e:
            logger.error(f"AppleScript error: {e}")

        return events

    def sync_events(self):

        logger.info("Starting calendar sync...")

        events = self.get_calendar_events_applescript()

        if not events:
            logger.info("AppleScript returned no events, trying EventKit...")
            events = self.get_calendar_events_eventkit()

        if not events:
            logger.info("EventKit returned no events, trying icalBuddy...")
            events = self.get_calendar_events_icalbuddy()

        self.events = events
        self.last_sync = datetime.now().isoformat()

        data = {
            'last_sync': self.last_sync,
            'event_count': len(events),
            'events': events
        }

        encrypt_file(data, CALENDAR_DATA_FILE)

        logger.info(f"Synced {len(events)} events to {CALENDAR_DATA_FILE}")
        return events

    def get_status(self):

        data = decrypt_file(CALENDAR_DATA_FILE)
        if data:
            return {
                'last_sync': data.get('last_sync'),
                'event_count': data.get('event_count', 0),
                'file_path': str(CALENDAR_DATA_FILE)
            }
        return {
            'last_sync': None,
            'event_count': 0,
            'file_path': str(CALENDAR_DATA_FILE)
        }

class CalendarSyncDaemon:

    def __init__(self):
        self.syncer = MacOSCalendarSync()
        self.running = False

    def start(self):

        if self.is_running():
            logger.warning("Daemon is already running")
            return False

        try:
            pid = os.fork()
            if pid > 0:

                print(f"Calendar sync daemon started (PID: {pid})")
                return True
        except OSError as e:
            logger.error(f"Fork failed: {e}")
            return False

        os.setsid()

        with open(PID_FILE, 'w') as f:
            f.write(str(os.getpid()))

        signal.signal(signal.SIGTERM, self._handle_signal)
        signal.signal(signal.SIGINT, self._handle_signal)

        self.running = True
        logger.info(f"Daemon started with PID {os.getpid()}")

        while self.running:
            try:
                self.syncer.sync_events()
            except Exception as e:
                logger.error(f"Sync error: {e}")

            time.sleep(SYNC_INTERVAL)

        if PID_FILE.exists():
            PID_FILE.unlink()
        logger.info("Daemon stopped")

    def stop(self):

        if not self.is_running():
            print("Daemon is not running")
            return False

        pid = self.get_pid()
        if pid:
            try:
                os.kill(pid, signal.SIGTERM)
                print(f"Sent SIGTERM to daemon (PID: {pid})")

                for _ in range(10):
                    try:
                        os.kill(pid, 0)
                        time.sleep(0.5)
                    except OSError:
                        break

                try:
                    os.kill(pid, 0)
                    os.kill(pid, signal.SIGKILL)
                    print("Daemon killed")
                except OSError:
                    pass

                if PID_FILE.exists():
                    PID_FILE.unlink()
                return True
            except OSError as e:
                logger.error(f"Could not stop daemon: {e}")
                if PID_FILE.exists():
                    PID_FILE.unlink()
                return False

        return False

    def is_running(self):

        pid = self.get_pid()
        if pid:
            try:
                os.kill(pid, 0)
                return True
            except OSError:

                if PID_FILE.exists():
                    PID_FILE.unlink()
        return False

    def get_pid(self):

        if PID_FILE.exists():
            try:
                with open(PID_FILE, 'r') as f:
                    return int(f.read().strip())
            except (ValueError, IOError):
                pass
        return None

    def _handle_signal(self, signum, frame):

        logger.info(f"Received signal {signum}, stopping daemon...")
        self.running = False

def main():
    parser = argparse.ArgumentParser(description=f'{BRAND_NAME} Calendar Sync Helper')
    parser.add_argument('--daemon', action='store_true', help='Run as background daemon')
    parser.add_argument('--sync', action='store_true', help='One-time sync')
    parser.add_argument('--status', action='store_true', help='Check sync status')
    parser.add_argument('--stop', action='store_true', help='Stop the daemon')
    args = parser.parse_args()

    daemon = CalendarSyncDaemon()
    syncer = MacOSCalendarSync()

    if args.daemon:
        daemon.start()
    elif args.stop:
        daemon.stop()
    elif args.sync:
        events = syncer.sync_events()
        print(f"Synced {len(events)} events")
    elif args.status:
        status = syncer.get_status()
        running = daemon.is_running()
        print(f"Daemon running: {running}")
        if running:
            print(f"Daemon PID: {daemon.get_pid()}")
        print(f"Last sync: {status['last_sync'] or 'Never'}")
        print(f"Events synced: {status['event_count']}")
        print(f"Data file: {status['file_path']}")
    else:
        parser.print_help()

if __name__ == '__main__':
    main()
