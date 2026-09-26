// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

var AppNotifications = {
    POLL_INTERVAL: 60000,
    SETTINGS_PREFIX: 'app-notif-',
    SHOWN_KEY: 'app-notif-shown',
    SHOWN_MAX_AGE: 86400000,

    BLOCK_TIMES: [
        { block: 1, start: '08:00', end: '09:30' },
        { block: 2, start: '09:50', end: '11:20' },
        { block: 3, start: '11:30', end: '13:00' },
        { block: 4, start: '13:30', end: '15:00' }
    ],

    _intervalId: null,
    _settings: null,
    _shownMap: null,
    _schoolSettings: null,
    _initDone: false,
    _toastContainer: null,


    init: function() {
        if (this._initDone) return;
        this._loadSettings();
        this._loadShownMap();

        console.log('[Notifications] init — enabled:', this._settings.enabled);

        if (!this._settings.enabled) return;

        this._initDone = true;
        this._ensureToastContainer();
        this._fetchSchoolSettings();

        console.log('[Notifications] Started polling (60s interval)');
        setTimeout(function() { AppNotifications._runChecks(); }, 5000);
        this._intervalId = setInterval(function() { AppNotifications._runChecks(); }, this.POLL_INTERVAL);

        if (!this._onVisibility) {
            this._onVisibility = function() {
                if (!document.hidden) {
                    AppNotifications._loadSettings();
                    if (AppNotifications._settings.enabled) {
                        AppNotifications._runChecks();
                    }
                }
            };
        }
        document.addEventListener('visibilitychange', this._onVisibility);
    },

    destroy: function() {
        if (this._intervalId) {
            clearInterval(this._intervalId);
            this._intervalId = null;
        }
        if (this._onVisibility) {
            document.removeEventListener('visibilitychange', this._onVisibility);
        }
        this._initDone = false;
    },

    restart: function() {
        this.destroy();
        this.init();
    },

    sendTestNotification: function() {
        this._loadSettings();
        this._ensureToastContainer();
        this._showNotification('test', `${BRAND_NAME} Test`, 'Benachrichtigungen funktionieren!', null, null);
    },

    notifyPomodoroComplete: function(isWorkComplete) {
        if (!this._shouldNotify('pomodoro')) return;
        var title = isWorkComplete ? 'Arbeitsphase beendet!' : 'Pause beendet!';
        var body = isWorkComplete ? 'Zeit für eine Pause.' : 'Zurück an die Arbeit!';
        var now = new Date();
        var key = 'pomodoro:' + (isWorkComplete ? 'work' : 'break') + ':' + now.toDateString() + ':' + now.getHours() + ':' + now.getMinutes();
        this._showNotification('pomodoro', title, body, '/hub/pomodoro', key);
    },


    _loadSettings: function() {
        this._settings = {
            enabled:      this._getBool('enabled', false),
            sound:        this._getBool('sound', true),
            quietStart:   this._getStr('quiet-start', '22:00'),
            quietEnd:     this._getStr('quiet-end', '07:00'),

            calendar:          this._getBool('cat-calendar', true),
            calendarReminders: this._getArr('cat-calendar-reminders', null),
            calendarLead:      this._getInt('cat-calendar-lead', 15), // legacy fallback

            tasks:        this._getBool('cat-tasks', true),

            homework:     this._getBool('cat-homework', true),
            homeworkLead: this._getInt('cat-homework-lead', 1),

            school:       this._getBool('cat-school', true),
            schoolLead:   this._getInt('cat-school-lead', 10),

            training:     this._getBool('cat-training', true),
            trainingLead: this._getInt('cat-training-lead', 15),

            pomodoro:     this._getBool('cat-pomodoro', true),

            tests:        this._getBool('cat-tests', true),
            testsLead:    this._getInt('cat-tests-lead', 1)
        };
    },

    _getBool: function(key, def) {
        var v = localStorage.getItem(this.SETTINGS_PREFIX + key);
        return v === null ? def : v === 'true';
    },

    _getStr: function(key, def) {
        return localStorage.getItem(this.SETTINGS_PREFIX + key) || def;
    },

    _getInt: function(key, def) {
        var v = localStorage.getItem(this.SETTINGS_PREFIX + key);
        return v === null ? def : parseInt(v, 10);
    },

    _getArr: function(key, def) {
        var v = localStorage.getItem(this.SETTINGS_PREFIX + key);
        if (!v) return def;
        try { return JSON.parse(v); } catch(e) { return def; }
    },


    _hasNativePermission: function() {
        return 'Notification' in window && Notification.permission === 'granted';
    },

    requestPermission: function() {
        if (!('Notification' in window)) return Promise.resolve('unsupported');
        if (Notification.permission === 'granted') return Promise.resolve('granted');
        if (Notification.permission === 'denied') return Promise.resolve('denied');
        return Notification.requestPermission();
    },


    _isQuietHours: function() {
        var now = new Date();
        var nowMin = now.getHours() * 60 + now.getMinutes();
        var parts = this._settings.quietStart.split(':');
        var startMin = parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
        parts = this._settings.quietEnd.split(':');
        var endMin = parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);

        if (startMin < endMin) {
            return nowMin >= startMin && nowMin < endMin;
        }
        return nowMin >= startMin || nowMin < endMin;
    },


    _loadShownMap: function() {
        try {
            this._shownMap = JSON.parse(localStorage.getItem(this.SHOWN_KEY) || '{}');
        } catch (e) { this._shownMap = {}; }
        this._pruneShownMap();
    },

    _pruneShownMap: function() {
        var cutoff = Date.now() - this.SHOWN_MAX_AGE;
        var changed = false;
        for (var key in this._shownMap) {
            if (this._shownMap[key] < cutoff) {
                delete this._shownMap[key];
                changed = true;
            }
        }
        if (changed) this._saveShownMap();
    },

    _saveShownMap: function() {
        localStorage.setItem(this.SHOWN_KEY, JSON.stringify(this._shownMap));
    },

    _wasShown: function(key) {
        return key in this._shownMap;
    },

    _markShown: function(key) {
        this._shownMap[key] = Date.now();
        this._saveShownMap();
    },


    _fetchSchoolSettings: function() {
        var self = this;
        fetch('/api/hub/school/timetable/settings')
            .then(function(r) { return r.json(); })
            .then(function(data) {
                var s = data.settings || {};
                self._schoolSettings = {
                    hasAbWeeks: s.has_ab_weeks !== undefined ? Boolean(s.has_ab_weeks) : true,
                    referenceDate: s.reference_date ? new Date(s.reference_date) : new Date(2026, 0, 12),
                    setupCompleted: Boolean(s.setup_completed)
                };
            })
            .catch(function() {
                self._schoolSettings = {
                    hasAbWeeks: true,
                    referenceDate: new Date(2026, 0, 12),
                    setupCompleted: false
                };
            });
    },

    _getWeekType: function(date) {
        if (!this._schoolSettings || !this._schoolSettings.hasAbWeeks) return 'A';

        var d = new Date(date);
        var dayOfWeek = d.getDay();
        var mondayOffset = dayOfWeek === 0 ? -6 : 1 - dayOfWeek;
        var monday = new Date(d);
        monday.setDate(d.getDate() + mondayOffset);
        monday.setHours(0, 0, 0, 0);

        var refMonday = new Date(this._schoolSettings.referenceDate);
        refMonday.setHours(0, 0, 0, 0);

        var diffTime = monday.getTime() - refMonday.getTime();
        var diffWeeks = Math.floor(diffTime / (7 * 24 * 60 * 60 * 1000));

        return diffWeeks % 2 === 0 ? 'A' : 'B';
    },


    _runChecks: function() {
        if (!this._settings.enabled) return;
        if (this._isQuietHours()) return;

        this._loadSettings();

        var checks = [];
        if (this._settings.calendar) checks.push(this._checkCalendar());
        if (this._settings.tasks) checks.push(this._checkTasks());
        if (this._settings.homework || this._settings.tests) checks.push(this._checkDeadlines());
        if (this._settings.school) checks.push(this._checkSchool());
        if (this._settings.training) checks.push(this._checkTraining());

        Promise.allSettled(checks);
    },


    _checkCalendar: function() {
        var self = this;
        return fetch('/api/calendar/events?days=1')
            .then(function(r) { return r.json(); })
            .then(function(data) {
                if (!data.success || !data.events) return;
                var now = new Date();
                var today = now.toISOString().split('T')[0];

                // Support multiple reminder offsets; fall back to legacy single value
                var reminders = self._settings.calendarReminders || [self._settings.calendarLead];

                data.events.forEach(function(evt) {
                    if (!evt.start_time || !evt.start_date) return;
                    if (evt.start_date !== today) return;

                    var parts = evt.start_time.split(':');
                    var evtDate = new Date(now);
                    evtDate.setHours(parseInt(parts[0], 10), parseInt(parts[1], 10), 0, 0);

                    var diffMin = (evtDate.getTime() - now.getTime()) / 60000;
                    if (diffMin <= 0) return; // event already started

                    var evtId = evt.event_id || evt.title;

                    reminders.forEach(function(leadMinutes) {
                        if (diffMin > leadMinutes) return; // not yet in this window
                        var key = 'calendar:' + evtId + ':' + today + ':r' + leadMinutes;
                        if (self._wasShown(key)) return;

                        var mins = Math.round(diffMin);
                        var body = mins <= 1 ? 'Gleich' : 'In ' + mins + ' Min';
                        if (evt.location) body += ' \u2014 ' + evt.location;

                        self._showNotification('calendar', evt.title, body, '/hub/calendar', key);
                    });
                });
            })
            .catch(function() {});
    },

    _checkTasks: function() {
        var self = this;
        var today = new Date().toDateString();

        return Promise.all([
            fetch('/api/hub/tasks?filter=today').then(function(r) { return r.json(); }),
            fetch('/api/hub/tasks?filter=overdue').then(function(r) { return r.json(); })
        ]).then(function(results) {
            var todayData = results[0];
            var overdueData = results[1];

            if (todayData.success && todayData.tasks) {
                var dueTasks = todayData.tasks.filter(function(t) { return !t.completed; });
                if (dueTasks.length > 0) {
                    var key = 'tasks:due:' + today;
                    if (!self._wasShown(key)) {
                        var titles = dueTasks.slice(0, 3).map(function(t) { return t.title; }).join(', ');
                        var title = dueTasks.length + ' Aufgabe' + (dueTasks.length > 1 ? 'n' : '') + ' f\u00e4llig';
                        self._showNotification('tasks', title, titles, '/hub/tasks', key);
                    }
                }
            }

            if (overdueData.success && overdueData.tasks) {
                var overdue = overdueData.tasks.filter(function(t) { return !t.completed; });
                if (overdue.length > 0) {
                    var key = 'tasks:overdue:' + today;
                    if (!self._wasShown(key)) {
                        var titles = overdue.slice(0, 3).map(function(t) { return t.title; }).join(', ');
                        var title = overdue.length + ' \u00fcberf\u00e4llige Aufgabe' + (overdue.length > 1 ? 'n' : '');
                        self._showNotification('tasks', title, titles, '/hub/tasks', key);
                    }
                }
            }
        }).catch(function() {});
    },

    _checkDeadlines: function() {
        var self = this;
        var maxDays = Math.max(
            self._settings.homework ? self._settings.homeworkLead : 0,
            self._settings.tests ? self._settings.testsLead : 0
        );
        if (maxDays < 1) maxDays = 7;

        return fetch('/api/deadlines?days=' + (maxDays + 1))
            .then(function(r) { return r.json(); })
            .then(function(data) {
                if (!data.success || !data.deadlines) return;
                var today = new Date().toDateString();

                data.deadlines.forEach(function(item) {
                    var daysUntil = item.days_until !== undefined ? item.days_until : 999;

                    if (item.type === 'homework' && self._settings.homework && daysUntil <= self._settings.homeworkLead) {
                        var key = 'homework:' + item.id + ':' + today;
                        if (self._wasShown(key)) return;
                        var when = daysUntil === 0 ? 'F\u00e4llig heute' : 'F\u00e4llig morgen';
                        if (daysUntil > 1) when = 'F\u00e4llig in ' + daysUntil + ' Tagen';
                        self._showNotification('homework', 'Hausaufgabe: ' + item.title, when, '/hub/school', key);
                    }

                    if (item.type === 'test' && self._settings.tests && daysUntil <= self._settings.testsLead) {
                        var key = 'test:' + item.id + ':' + today;
                        if (self._wasShown(key)) return;
                        var when = daysUntil === 0 ? 'Heute' : (daysUntil === 1 ? 'Morgen' : 'In ' + daysUntil + ' Tagen');
                        self._showNotification('tests', 'Test: ' + item.title, when, '/hub/school', key);
                    }

                    if (item.type === 'exam' && self._settings.tests && daysUntil <= self._settings.testsLead) {
                        var key = 'exam:' + item.id + ':' + today;
                        if (self._wasShown(key)) return;
                        var when = daysUntil === 0 ? 'Heute' : (daysUntil === 1 ? 'Morgen' : 'In ' + daysUntil + ' Tagen');
                        self._showNotification('tests', 'Klausur: ' + item.title, when, '/hub/school', key);
                    }
                });
            })
            .catch(function() {});
    },

    _checkSchool: function() {
        var self = this;
        if (!self._schoolSettings || !self._schoolSettings.setupCompleted) return Promise.resolve();

        var now = new Date();
        var dayOfWeek = now.getDay();
        if (dayOfWeek === 0 || dayOfWeek === 6) return Promise.resolve();

        var week = self._getWeekType(now);

        return fetch('/api/hub/school/timetable/entries?day=' + dayOfWeek + '&week=' + week)
            .then(function(r) { return r.json(); })
            .then(function(data) {
                if (!data.success || !data.entries) return;

                var nowMin = now.getHours() * 60 + now.getMinutes();
                var today = now.toDateString();

                var blockMap = {};
                data.entries.forEach(function(entry) {
                    blockMap[entry.block] = entry;
                });

                self.BLOCK_TIMES.forEach(function(bt) {
                    var entry = blockMap[bt.block];
                    if (!entry) return;

                    var parts = bt.start.split(':');
                    var blockStartMin = parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
                    var diffMin = blockStartMin - nowMin;

                    if (diffMin > 0 && diffMin <= self._settings.schoolLead) {
                        var key = 'school:block-' + bt.block + ':' + today;
                        if (self._wasShown(key)) return;

                        var body = 'In ' + Math.round(diffMin) + ' Min';
                        if (entry.room) body += ' \u2014 Raum ' + entry.room;

                        self._showNotification('school', 'N\u00e4chste Stunde: ' + entry.subject, body, '/hub/school', key);
                    }
                });
            })
            .catch(function() {});
    },

    _checkTraining: function() {
        var self = this;
        var now = new Date();
        var dayOfWeek = now.getDay();

        return fetch('/api/hub/training/schedule/entries?day=' + dayOfWeek)
            .then(function(r) { return r.json(); })
            .then(function(data) {
                if (!data.success || !data.entries) return;
                var nowMin = now.getHours() * 60 + now.getMinutes();
                var today = now.toDateString();

                data.entries.forEach(function(entry) {
                    if (!entry.time) return;

                    var parts = entry.time.split(':');
                    var entryMin = parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
                    var diffMin = entryMin - nowMin;

                    if (diffMin > 0 && diffMin <= self._settings.trainingLead) {
                        var key = 'training:' + entry.id + ':' + today;
                        if (self._wasShown(key)) return;

                        var title = 'Training: ' + (entry.title || entry.training_type || 'Einheit');
                        var body = 'In ' + Math.round(diffMin) + ' Min';
                        if (entry.location) body += ' \u2014 ' + entry.location;

                        self._showNotification('training', title, body, '/hub/training', key);
                    }
                });
            })
            .catch(function() {});
    },


    _isInFlutterWebView: function() {
        return !!(window.flutter_inappwebview);
    },

    _showNotification: function(category, title, body, url, key) {
        if (key && this._wasShown(key)) return;

        if (this._isInFlutterWebView()) {
            // Route through Flutter → macOS native notification system (no in-app toast)
            try {
                window.flutter_inappwebview.callHandler('showNativeNotification', {
                    title: title,
                    body: body
                });
            } catch (e) {}
        } else {
            // Browser fallback: show in-app toast + Web Notification API
            if (this._settings.sound) this._playSound();
            this._showToast(category, title, body, url);

            if (this._hasNativePermission()) {
                try {
                    var notif = new Notification(title, {
                        body: body,
                        icon: '/static/images/icons/icon-192.png',
                        tag: 'app-' + category + '-' + Date.now()
                    });
                    if (url) {
                        notif.onclick = function() {
                            window.focus();
                            window.location.href = url;
                            notif.close();
                        };
                    }
                } catch (e) {}
            }
        }

        if (key) this._markShown(key);
    },


    _ensureToastContainer: function() {
        if (this._toastContainer && document.body.contains(this._toastContainer)) return;
        var c = document.createElement('div');
        c.id = 'app-notif-container';
        c.style.cssText = 'position:fixed;top:16px;right:16px;z-index:10000;display:flex;flex-direction:column;gap:8px;pointer-events:none;max-width:380px;width:calc(100% - 32px);';
        document.body.appendChild(c);
        this._toastContainer = c;
    },

    _getCategoryIcon: function(category) {
        var icons = {
            calendar: '<path d="M8 2v4M16 2v4M3 10h18M5 4h14a2 2 0 012 2v14a2 2 0 01-2 2H5a2 2 0 01-2-2V6a2 2 0 012-2z"/>',
            tasks: '<path d="M9 11l3 3L22 4M21 12v7a2 2 0 01-2 2H5a2 2 0 01-2-2V5a2 2 0 012-2h11"/>',
            homework: '<path d="M2 3h6a4 4 0 014 4v14a3 3 0 00-3-3H2z"/><path d="M22 3h-6a4 4 0 00-4 4v14a3 3 0 013-3h7z"/>',
            school: '<path d="M22 10v6M2 10l10-5 10 5-10 5z"/><path d="M6 12v5c3 3 9 3 12 0v-5"/>',
            training: '<path d="M18 8h1a4 4 0 010 8h-1M2 8h16v9a4 4 0 01-4 4H6a4 4 0 01-4-4V8z"/><line x1="6" y1="1" x2="6" y2="4"/><line x1="10" y1="1" x2="10" y2="4"/><line x1="14" y1="1" x2="14" y2="4"/>',
            pomodoro: '<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>',
            tests: '<path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/>',
            test: '<svg></svg>'
        };
        return icons[category] || icons.calendar;
    },

    _getCategoryColor: function(category) {
        var colors = {
            calendar: 'var(--hue-lake, #0C7491)',
            tasks: 'var(--hue-ochre, #9A6A1E)',
            homework: 'var(--hue-iris, #635DAB)',
            school: 'var(--hue-jade, #0D7C59)',
            training: 'var(--hue-rose, #C1657E)',
            pomodoro: 'var(--danger, #C96F4F)',
            tests: 'var(--hue-brick, #A34943)',
            test: 'var(--hue-lake, #0C7491)'
        };
        return colors[category] || 'var(--hue-lake, #0C7491)';
    },

    _showToast: function(category, title, body, url) {
        this._ensureToastContainer();

        var color = this._getCategoryColor(category);
        var iconPath = this._getCategoryIcon(category);

        // Wrapper — no background, no border, just holds the blur layer + content
        var toast = document.createElement('div');
        toast.style.cssText = 'pointer-events:auto;position:relative;overflow:visible;cursor:pointer;opacity:0;transform:translateX(40px);transition:opacity 0.3s ease,transform 0.3s ease;max-width:100%;';

        // Blur layer with gradient-masked edges (fades from full blur → none)
        var surface = document.createElement('div');
        surface.style.cssText = 'position:absolute;inset:0;border-radius:20px;background:var(--bg-overlay, #FFFFFF);box-shadow:var(--shadow-float, 0 0 0 1px #E4DFD4, 0 14px 36px -10px rgba(46, 58, 47, 0.24));pointer-events:none;';
        toast.appendChild(surface);

        // Content layer sits above the blur
        var content = document.createElement('div');
        content.style.cssText = 'position:relative;z-index:1;display:flex;align-items:flex-start;gap:12px;padding:14px 16px;';

        var iconSvg = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="flex-shrink:0;margin-top:2px;stroke:' + color + ';">' + iconPath + '</svg>';

        var textHtml = '<div style="flex:1;min-width:0;">' +
            '<div style="font-size:14px;font-weight:600;color:var(--text-primary, #2E3A2F);line-height:1.3;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">' + this._escapeHtml(title) + '</div>' +
            '<div style="font-size:12px;color:var(--text-muted, #5E665B);line-height:1.4;margin-top:2px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">' + this._escapeHtml(body) + '</div>' +
            '</div>';

        var closeBtn = '<div style="flex-shrink:0;color:var(--text-muted, #5E665B);font-size:18px;line-height:1;padding:0 0 0 4px;cursor:pointer;" data-close="1">&times;</div>';

        content.innerHTML = iconSvg + textHtml + closeBtn;
        toast.appendChild(content);

        if (url) {
            toast.addEventListener('click', function(e) {
                if (e.target.getAttribute('data-close') === '1') return;
                window.location.href = url;
            });
        }

        content.querySelector('[data-close]').addEventListener('click', function(e) {
            e.stopPropagation();
            toast.style.opacity = '0';
            toast.style.transform = 'translateX(40px)';
            setTimeout(function() { toast.remove(); }, 300);
        });

        this._toastContainer.appendChild(toast);

        requestAnimationFrame(function() {
            requestAnimationFrame(function() {
                toast.style.opacity = '1';
                toast.style.transform = 'translateX(0)';
            });
        });

        setTimeout(function() {
            if (!toast.parentNode) return;
            toast.style.opacity = '0';
            toast.style.transform = 'translateX(40px)';
            setTimeout(function() { toast.remove(); }, 300);
        }, 6000);
    },

    _escapeHtml: function(str) {
        if (!str) return '';
        return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    },

    _playSound: function() {
        try {
            var ctx = new (window.AudioContext || window.webkitAudioContext)();
            var osc = ctx.createOscillator();
            var gain = ctx.createGain();
            osc.connect(gain);
            gain.connect(ctx.destination);
            osc.frequency.value = 800;
            osc.type = 'sine';
            gain.gain.setValueAtTime(0.3, ctx.currentTime);
            gain.gain.exponentialRampToValueAtTime(0.01, ctx.currentTime + 0.5);
            osc.start(ctx.currentTime);
            osc.stop(ctx.currentTime + 0.5);
        } catch (e) {}
    },

    _shouldNotify: function(category) {
        if (!this._settings) this._loadSettings();
        if (!this._settings.enabled) return false;
        if (this._isQuietHours()) return false;
        return this._settings[category] === true;
    }
};
