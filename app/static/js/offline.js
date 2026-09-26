// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const AppDB = {
    db: null,
    DB_NAME: 'app-hub',
    DB_VERSION: 2,

    STORES: {
        accounts: 'accounts',
        tasks: 'tasks',
        timetable_entries: 'timetable_entries',
        timetable_settings: 'timetable_settings',
        grades: 'grades',
        homework: 'homework',
        tests: 'tests',
        exams: 'exams',
        reviews: 'reviews',
        training_sessions: 'training_sessions',
        training_health: 'training_health',
        training_goals: 'training_goals',
        quick_notes: 'quick_notes',
        school_calendar: 'school_calendar',
        subjects: 'subjects',
        sync_queue: 'sync_queue'
    },

    RETIRED_STORES: ['projects', 'knowledge'],

    async init() {
        return new Promise((resolve, reject) => {
            const request = indexedDB.open(this.DB_NAME, this.DB_VERSION);

            request.onerror = () => reject(request.error);
            request.onsuccess = () => {
                this.db = request.result;
                resolve(this.db);
            };

            request.onupgradeneeded = (event) => {
                const db = event.target.result;

                if (!db.objectStoreNames.contains(this.STORES.accounts)) {
                    const accountsStore = db.createObjectStore(this.STORES.accounts, { keyPath: 'id', autoIncrement: true });
                    accountsStore.createIndex('username', 'username', { unique: true });
                }

                if (!db.objectStoreNames.contains(this.STORES.tasks)) {
                    const tasksStore = db.createObjectStore(this.STORES.tasks, { keyPath: 'id', autoIncrement: true });
                    tasksStore.createIndex('user_id', 'user_id', { unique: false });
                    tasksStore.createIndex('completed', 'completed', { unique: false });
                }

                if (!db.objectStoreNames.contains(this.STORES.timetable_entries)) {
                    const timetableStore = db.createObjectStore(this.STORES.timetable_entries, { keyPath: 'id', autoIncrement: true });
                    timetableStore.createIndex('user_id', 'user_id', { unique: false });
                    timetableStore.createIndex('day_block', ['user_id', 'day', 'block'], { unique: false });
                }

                if (!db.objectStoreNames.contains(this.STORES.timetable_settings)) {
                    const settingsStore = db.createObjectStore(this.STORES.timetable_settings, { keyPath: 'user_id' });
                }

                if (!db.objectStoreNames.contains(this.STORES.grades)) {
                    const gradesStore = db.createObjectStore(this.STORES.grades, { keyPath: 'id', autoIncrement: true });
                    gradesStore.createIndex('user_id', 'user_id', { unique: false });
                    gradesStore.createIndex('subject', ['user_id', 'subject'], { unique: false });
                }

                if (!db.objectStoreNames.contains(this.STORES.homework)) {
                    const homeworkStore = db.createObjectStore(this.STORES.homework, { keyPath: 'id', autoIncrement: true });
                    homeworkStore.createIndex('user_id', 'user_id', { unique: false });
                }

                if (!db.objectStoreNames.contains(this.STORES.tests)) {
                    const testsStore = db.createObjectStore(this.STORES.tests, { keyPath: 'id', autoIncrement: true });
                    testsStore.createIndex('user_id', 'user_id', { unique: false });
                }

                if (!db.objectStoreNames.contains(this.STORES.exams)) {
                    const examsStore = db.createObjectStore(this.STORES.exams, { keyPath: 'id', autoIncrement: true });
                    examsStore.createIndex('user_id', 'user_id', { unique: false });
                }

                if (!db.objectStoreNames.contains(this.STORES.reviews)) {
                    const reviewsStore = db.createObjectStore(this.STORES.reviews, { keyPath: 'id', autoIncrement: true });
                    reviewsStore.createIndex('user_id', 'user_id', { unique: false });
                    reviewsStore.createIndex('date', ['user_id', 'date'], { unique: false });
                }

                if (!db.objectStoreNames.contains(this.STORES.training_sessions)) {
                    const sessionsStore = db.createObjectStore(this.STORES.training_sessions, { keyPath: 'id', autoIncrement: true });
                    sessionsStore.createIndex('user_id', 'user_id', { unique: false });
                }

                if (!db.objectStoreNames.contains(this.STORES.training_health)) {
                    const healthStore = db.createObjectStore(this.STORES.training_health, { keyPath: 'id', autoIncrement: true });
                    healthStore.createIndex('user_id', 'user_id', { unique: false });
                    healthStore.createIndex('date', ['user_id', 'date'], { unique: false });
                }

                if (!db.objectStoreNames.contains(this.STORES.training_goals)) {
                    const goalsStore = db.createObjectStore(this.STORES.training_goals, { keyPath: 'id', autoIncrement: true });
                    goalsStore.createIndex('user_id', 'user_id', { unique: false });
                }

                if (!db.objectStoreNames.contains(this.STORES.quick_notes)) {
                    const notesStore = db.createObjectStore(this.STORES.quick_notes, { keyPath: 'id', autoIncrement: true });
                    notesStore.createIndex('user_id', 'user_id', { unique: false });
                }

                if (!db.objectStoreNames.contains(this.STORES.school_calendar)) {
                    const calendarStore = db.createObjectStore(this.STORES.school_calendar, { keyPath: 'id', autoIncrement: true });
                    calendarStore.createIndex('user_id', 'user_id', { unique: false });
                }

                if (!db.objectStoreNames.contains(this.STORES.subjects)) {
                    const subjectsStore = db.createObjectStore(this.STORES.subjects, { keyPath: 'id', autoIncrement: true });
                    subjectsStore.createIndex('user_id', 'user_id', { unique: false });
                }

                if (!db.objectStoreNames.contains(this.STORES.sync_queue)) {
                    const syncStore = db.createObjectStore(this.STORES.sync_queue, { keyPath: 'id', autoIncrement: true });
                    syncStore.createIndex('timestamp', 'timestamp', { unique: false });
                }

                const upgrade = event.target.transaction;
                for (const name of this.RETIRED_STORES) {
                    if (!db.objectStoreNames.contains(name)) continue;
                    const count = upgrade.objectStore(name).count();
                    count.onsuccess = () => {
                        if (count.result === 0) db.deleteObjectStore(name);
                    };
                }
            };
        });
    },

    async add(storeName, data) {
        return new Promise((resolve, reject) => {
            const transaction = this.db.transaction([storeName], 'readwrite');
            const store = transaction.objectStore(storeName);
            const request = store.add(data);
            request.onsuccess = () => resolve(request.result);
            request.onerror = () => reject(request.error);
        });
    },

    async put(storeName, data) {
        return new Promise((resolve, reject) => {
            const transaction = this.db.transaction([storeName], 'readwrite');
            const store = transaction.objectStore(storeName);
            const request = store.put(data);
            request.onsuccess = () => resolve(request.result);
            request.onerror = () => reject(request.error);
        });
    },

    async get(storeName, id) {
        return new Promise((resolve, reject) => {
            const transaction = this.db.transaction([storeName], 'readonly');
            const store = transaction.objectStore(storeName);
            const request = store.get(id);
            request.onsuccess = () => resolve(request.result);
            request.onerror = () => reject(request.error);
        });
    },

    async getAll(storeName) {
        return new Promise((resolve, reject) => {
            const transaction = this.db.transaction([storeName], 'readonly');
            const store = transaction.objectStore(storeName);
            const request = store.getAll();
            request.onsuccess = () => resolve(request.result);
            request.onerror = () => reject(request.error);
        });
    },

    async getAllByIndex(storeName, indexName, value) {
        return new Promise((resolve, reject) => {
            const transaction = this.db.transaction([storeName], 'readonly');
            const store = transaction.objectStore(storeName);
            const index = store.index(indexName);
            const request = index.getAll(value);
            request.onsuccess = () => resolve(request.result);
            request.onerror = () => reject(request.error);
        });
    },

    async delete(storeName, id) {
        return new Promise((resolve, reject) => {
            const transaction = this.db.transaction([storeName], 'readwrite');
            const store = transaction.objectStore(storeName);
            const request = store.delete(id);
            request.onsuccess = () => resolve(true);
            request.onerror = () => reject(request.error);
        });
    },

    async clear(storeName) {
        return new Promise((resolve, reject) => {
            const transaction = this.db.transaction([storeName], 'readwrite');
            const store = transaction.objectStore(storeName);
            const request = store.clear();
            request.onsuccess = () => resolve(true);
            request.onerror = () => reject(request.error);
        });
    }
};

const AppAccounts = {
    currentAccount: null,
    STORAGE_KEY: 'app_current_account',

    async init() {
        await AppDB.init();

        const savedAccountId = localStorage.getItem(this.STORAGE_KEY);
        if (savedAccountId) {
            this.currentAccount = await AppDB.get(AppDB.STORES.accounts, parseInt(savedAccountId));
        }

        const accounts = await this.getAllAccounts();

        if (accounts.length === 0) {
            const defaultAccount = await this.createAccount('Benutzer', 'Benutzer', '#4285f4');
            await this.switchAccount(defaultAccount.id);
            return this.currentAccount;
        }

        if (!this.currentAccount && accounts.length > 0) {
            await this.switchAccount(accounts[0].id);
        }

        return this.currentAccount;
    },

    async createAccount(username, displayName = null, avatarColor = null) {

        const accounts = await this.getAllAccounts();
        if (accounts.some(a => a.username.toLowerCase() === username.toLowerCase())) {
            throw new Error('Benutzername existiert bereits');
        }

        const colors = ['#4285f4', '#ea4335', '#34a853', '#fbbc04', '#9c27b0', '#e91e63', '#00bcd4', '#ff5722'];
        const color = avatarColor || colors[Math.floor(Math.random() * colors.length)];

        const account = {
            username: username,
            display_name: displayName || username,
            avatar_color: color,
            created_at: new Date().toISOString(),
            last_login: new Date().toISOString()
        };

        const id = await AppDB.add(AppDB.STORES.accounts, account);
        account.id = id;

        await AppDB.put(AppDB.STORES.timetable_settings, {
            user_id: id,
            has_ab_weeks: true,
            block_count: 4,
            reference_date: null,
            setup_completed: false
        });

        return account;
    },

    async getAllAccounts() {
        return await AppDB.getAll(AppDB.STORES.accounts);
    },

    async switchAccount(accountId) {
        const account = await AppDB.get(AppDB.STORES.accounts, accountId);
        if (!account) {
            throw new Error('Konto nicht gefunden');
        }

        account.last_login = new Date().toISOString();
        await AppDB.put(AppDB.STORES.accounts, account);

        localStorage.setItem(this.STORAGE_KEY, accountId.toString());
        this.currentAccount = account;

        window.dispatchEvent(new CustomEvent('app-account-changed', { detail: account }));

        return account;
    },

    async updateAccount(accountId, updates) {
        const account = await AppDB.get(AppDB.STORES.accounts, accountId);
        if (!account) {
            throw new Error('Konto nicht gefunden');
        }

        if (updates.username && updates.username !== account.username) {
            const accounts = await this.getAllAccounts();
            if (accounts.some(a => a.id !== accountId && a.username.toLowerCase() === updates.username.toLowerCase())) {
                throw new Error('Benutzername existiert bereits');
            }
        }

        Object.assign(account, updates);
        await AppDB.put(AppDB.STORES.accounts, account);

        if (this.currentAccount && this.currentAccount.id === accountId) {
            this.currentAccount = account;
            window.dispatchEvent(new CustomEvent('app-account-changed', { detail: account }));
        }

        return account;
    },

    async deleteAccount(accountId) {

        const stores = Object.values(AppDB.STORES).filter(s => s !== 'accounts' && s !== 'sync_queue');

        for (const storeName of stores) {
            try {
                const items = await AppDB.getAllByIndex(storeName, 'user_id', accountId);
                for (const item of items) {
                    await AppDB.delete(storeName, item.id);
                }
            } catch (e) {

                if (storeName === 'timetable_settings') {
                    await AppDB.delete(storeName, accountId);
                }
            }
        }

        await AppDB.delete(AppDB.STORES.accounts, accountId);

        if (this.currentAccount && this.currentAccount.id === accountId) {
            localStorage.removeItem(this.STORAGE_KEY);
            this.currentAccount = null;

            const accounts = await this.getAllAccounts();
            if (accounts.length > 0) {
                await this.switchAccount(accounts[0].id);
            } else {
                window.dispatchEvent(new CustomEvent('app-account-changed', { detail: null }));
            }
        }

        return true;
    },

    getCurrentUserId() {
        return this.currentAccount ? this.currentAccount.id : null;
    },

    isLoggedIn() {
        return this.currentAccount !== null;
    }
};

const AppData = {

    getUserId() {
        const userId = AppAccounts.getCurrentUserId();
        if (!userId) {
            throw new Error('Kein Benutzer angemeldet');
        }
        return userId;
    },

    async getTasks(filter = 'all') {
        const userId = this.getUserId();
        let tasks = await AppDB.getAllByIndex(AppDB.STORES.tasks, 'user_id', userId);

        if (filter === 'today') {
            const today = new Date().toISOString().split('T')[0];
            tasks = tasks.filter(t => t.due_date === today && !t.completed);
        } else if (filter === 'upcoming') {
            const today = new Date().toISOString().split('T')[0];
            tasks = tasks.filter(t => t.due_date > today && !t.completed);
        } else if (filter === 'completed') {
            tasks = tasks.filter(t => t.completed);
        } else if (filter === 'overdue') {
            const today = new Date().toISOString().split('T')[0];
            tasks = tasks.filter(t => t.due_date < today && !t.completed);
        }

        tasks.sort((a, b) => {
            if (!a.due_date) return 1;
            if (!b.due_date) return -1;
            return a.due_date.localeCompare(b.due_date);
        });

        return tasks;
    },

    async createTask(data) {
        const task = {
            ...data,
            user_id: this.getUserId(),
            completed: false,
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString()
        };
        const id = await AppDB.add(AppDB.STORES.tasks, task);
        task.id = id;
        return task;
    },

    async updateTask(id, updates) {
        const task = await AppDB.get(AppDB.STORES.tasks, id);
        if (!task || task.user_id !== this.getUserId()) {
            throw new Error('Aufgabe nicht gefunden');
        }
        Object.assign(task, updates, { updated_at: new Date().toISOString() });
        await AppDB.put(AppDB.STORES.tasks, task);
        return task;
    },

    async toggleTask(id) {
        const task = await AppDB.get(AppDB.STORES.tasks, id);
        if (!task || task.user_id !== this.getUserId()) {
            throw new Error('Aufgabe nicht gefunden');
        }
        task.completed = !task.completed;
        task.completed_at = task.completed ? new Date().toISOString() : null;
        task.updated_at = new Date().toISOString();
        await AppDB.put(AppDB.STORES.tasks, task);
        return task;
    },

    async deleteTask(id) {
        const task = await AppDB.get(AppDB.STORES.tasks, id);
        if (!task || task.user_id !== this.getUserId()) {
            throw new Error('Aufgabe nicht gefunden');
        }
        await AppDB.delete(AppDB.STORES.tasks, id);
        return true;
    },

    async getTimetableSettings() {
        const userId = this.getUserId();
        return await AppDB.get(AppDB.STORES.timetable_settings, userId);
    },

    async saveTimetableSettings(settings) {
        const userId = this.getUserId();
        const data = {
            user_id: userId,
            ...settings,
            updated_at: new Date().toISOString()
        };
        await AppDB.put(AppDB.STORES.timetable_settings, data);
        return data;
    },

    async getTimetableEntries(day = null, week = null) {
        const userId = this.getUserId();
        let entries = await AppDB.getAllByIndex(AppDB.STORES.timetable_entries, 'user_id', userId);

        if (day !== null) {
            entries = entries.filter(e => e.day === day);
        }
        if (week !== null) {
            entries = entries.filter(e => e.week === week || e.week === 'both');
        }

        entries.sort((a, b) => {
            if (a.day !== b.day) return a.day - b.day;
            return a.block - b.block;
        });

        return entries;
    },

    async createTimetableEntry(data) {
        const entry = {
            ...data,
            user_id: this.getUserId(),
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString()
        };
        const id = await AppDB.add(AppDB.STORES.timetable_entries, entry);
        entry.id = id;
        return entry;
    },

    async updateTimetableEntry(id, updates) {
        const entry = await AppDB.get(AppDB.STORES.timetable_entries, id);
        if (!entry || entry.user_id !== this.getUserId()) {
            throw new Error('Eintrag nicht gefunden');
        }
        Object.assign(entry, updates, { updated_at: new Date().toISOString() });
        await AppDB.put(AppDB.STORES.timetable_entries, entry);
        return entry;
    },

    async deleteTimetableEntry(id) {
        const entry = await AppDB.get(AppDB.STORES.timetable_entries, id);
        if (!entry || entry.user_id !== this.getUserId()) {
            throw new Error('Eintrag nicht gefunden');
        }
        await AppDB.delete(AppDB.STORES.timetable_entries, id);
        return true;
    },

    async clearTimetable() {
        const userId = this.getUserId();
        const entries = await AppDB.getAllByIndex(AppDB.STORES.timetable_entries, 'user_id', userId);
        for (const entry of entries) {
            await AppDB.delete(AppDB.STORES.timetable_entries, entry.id);
        }
        return entries.length;
    },

    async importTimetableTemplate(entries) {
        const userId = this.getUserId();
        let count = 0;
        for (const entry of entries) {
            const data = {
                ...entry,
                user_id: userId,
                created_at: new Date().toISOString(),
                updated_at: new Date().toISOString()
            };
            delete data.id;
            await AppDB.add(AppDB.STORES.timetable_entries, data);
            count++;
        }
        return count;
    },

    async getReviews(type = null, limit = 50) {
        const userId = this.getUserId();
        let reviews = await AppDB.getAllByIndex(AppDB.STORES.reviews, 'user_id', userId);

        if (type) {
            reviews = reviews.filter(r => r.type === type);
        }

        reviews.sort((a, b) => new Date(b.date) - new Date(a.date));
        return reviews.slice(0, limit);
    },

    async getReviewByDate(date, type = 'daily') {
        const userId = this.getUserId();
        const reviews = await AppDB.getAllByIndex(AppDB.STORES.reviews, 'user_id', userId);
        return reviews.find(r => r.date === date && r.type === type);
    },

    async createReview(data) {
        const review = {
            ...data,
            user_id: this.getUserId(),
            type: data.type || 'daily',
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString()
        };
        const id = await AppDB.add(AppDB.STORES.reviews, review);
        review.id = id;
        return review;
    },

    async updateReview(id, updates) {
        const review = await AppDB.get(AppDB.STORES.reviews, id);
        if (!review || review.user_id !== this.getUserId()) {
            throw new Error('Review nicht gefunden');
        }
        Object.assign(review, updates, { updated_at: new Date().toISOString() });
        await AppDB.put(AppDB.STORES.reviews, review);
        return review;
    },

    async deleteReview(id) {
        const review = await AppDB.get(AppDB.STORES.reviews, id);
        if (!review || review.user_id !== this.getUserId()) {
            throw new Error('Review nicht gefunden');
        }
        await AppDB.delete(AppDB.STORES.reviews, id);
        return true;
    },

    async getTrainingSessions(type = null, limit = 50) {
        const userId = this.getUserId();
        let sessions = await AppDB.getAllByIndex(AppDB.STORES.training_sessions, 'user_id', userId);

        if (type) {
            sessions = sessions.filter(s => s.type === type);
        }

        sessions.sort((a, b) => new Date(b.date) - new Date(a.date));
        return sessions.slice(0, limit);
    },

    async createTrainingSession(data) {
        const session = {
            ...data,
            user_id: this.getUserId(),
            created_at: new Date().toISOString()
        };
        const id = await AppDB.add(AppDB.STORES.training_sessions, session);
        session.id = id;
        return session;
    },

    async updateTrainingSession(id, updates) {
        const session = await AppDB.get(AppDB.STORES.training_sessions, id);
        if (!session || session.user_id !== this.getUserId()) {
            throw new Error('Session nicht gefunden');
        }
        Object.assign(session, updates);
        await AppDB.put(AppDB.STORES.training_sessions, session);
        return session;
    },

    async deleteTrainingSession(id) {
        const session = await AppDB.get(AppDB.STORES.training_sessions, id);
        if (!session || session.user_id !== this.getUserId()) {
            throw new Error('Session nicht gefunden');
        }
        await AppDB.delete(AppDB.STORES.training_sessions, id);
        return true;
    },

    async getTrainingGoals(completed = null) {
        const userId = this.getUserId();
        let goals = await AppDB.getAllByIndex(AppDB.STORES.training_goals, 'user_id', userId);

        if (completed !== null) {
            goals = goals.filter(g => g.completed === completed);
        }

        goals.sort((a, b) => {
            if (!a.deadline) return 1;
            if (!b.deadline) return -1;
            return a.deadline.localeCompare(b.deadline);
        });

        return goals;
    },

    async createTrainingGoal(data) {
        const goal = {
            ...data,
            user_id: this.getUserId(),
            current: data.current || 0,
            completed: false,
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString()
        };
        const id = await AppDB.add(AppDB.STORES.training_goals, goal);
        goal.id = id;
        return goal;
    },

    async updateTrainingGoal(id, updates) {
        const goal = await AppDB.get(AppDB.STORES.training_goals, id);
        if (!goal || goal.user_id !== this.getUserId()) {
            throw new Error('Ziel nicht gefunden');
        }
        Object.assign(goal, updates, { updated_at: new Date().toISOString() });
        await AppDB.put(AppDB.STORES.training_goals, goal);
        return goal;
    },

    async deleteTrainingGoal(id) {
        const goal = await AppDB.get(AppDB.STORES.training_goals, id);
        if (!goal || goal.user_id !== this.getUserId()) {
            throw new Error('Ziel nicht gefunden');
        }
        await AppDB.delete(AppDB.STORES.training_goals, id);
        return true;
    }
};

document.addEventListener('DOMContentLoaded', async () => {
    try {
        await AppAccounts.init();
        console.log('Offline system initialized');

        window.dispatchEvent(new CustomEvent('app-ready', {
            detail: { account: AppAccounts.currentAccount }
        }));
    } catch (error) {
        console.error('Failed to initialize offline system:', error);
    }
});

window.AppDB = AppDB;
window.AppAccounts = AppAccounts;
window.AppData = AppData;
