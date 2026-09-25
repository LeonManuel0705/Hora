// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const AppConnection = {
    state: {
        internetAvailable: null,
        iservAvailable: null,
        lastCheck: null,
        checkInProgress: false
    },

    CACHE_KEY: 'app_connection_state',
    SESSION_KEY: 'app_session_started',
    CACHE_DURATION: 60000,
    PING_TIMEOUT: 500,
    INTERNET_TIMEOUT: 1500,

    async init() {

        this.loadCachedState();

        // Fast path: if browser says offline, skip all network probes
        if (!navigator.onLine) {
            this.state.internetAvailable = false;
            this.state.iservAvailable = false;
            this.saveState();
            window.dispatchEvent(new CustomEvent('app-connection-ready', {
                detail: this.state
            }));
            return this.state;
        }

        const isInitialLoad = !sessionStorage.getItem(this.SESSION_KEY);

        if (isInitialLoad || !this.state.lastCheck) {
            sessionStorage.setItem(this.SESSION_KEY, 'true');
            // Run connectivity check in background — don't block page render
            this.checkConnectivity().then(() => {
                window.dispatchEvent(new CustomEvent('app-connection-ready', {
                    detail: this.state
                }));
            });
        } else {
            window.dispatchEvent(new CustomEvent('app-connection-ready', {
                detail: this.state
            }));
        }

        return this.state;
    },

    loadCachedState() {
        try {
            const cached = sessionStorage.getItem(this.CACHE_KEY);
            if (cached) {
                const parsed = JSON.parse(cached);
                const age = Date.now() - parsed.lastCheck;
                if (age < this.CACHE_DURATION) {
                    Object.assign(this.state, parsed);
                    return true;
                }
            }
        } catch (e) {
            console.warn('Failed to load cached connection state:', e);
        }
        return false;
    },

    saveState() {
        this.state.lastCheck = Date.now();
        try {
            sessionStorage.setItem(this.CACHE_KEY, JSON.stringify(this.state));
        } catch (e) {
            console.warn('Failed to save connection state:', e);
        }
    },

    async checkConnectivity() {
        if (this.state.checkInProgress) return this.state;
        this.state.checkInProgress = true;

        try {
            if (!navigator.onLine) {
                this.state.internetAvailable = false;
                this.state.iservAvailable = false;
                this.saveState();
                return this.state;
            }

            const [internet, iserv] = await Promise.allSettled([
                this.checkInternet(),
                this.checkIServ()
            ]);

            this.state.internetAvailable = internet.status === 'fulfilled' && internet.value;
            this.state.iservAvailable = iserv.status === 'fulfilled' && iserv.value;

            this.saveState();
        } catch (e) {
            console.error('Connection check failed:', e);
        } finally {
            this.state.checkInProgress = false;
        }

        return this.state;
    },

    async checkInternet() {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), this.INTERNET_TIMEOUT);

        try {
            await fetch('https://connectivitycheck.gstatic.com/generate_204', {
                method: 'HEAD',
                mode: 'no-cors',
                signal: controller.signal,
                cache: 'no-store'
            });
            clearTimeout(timeoutId);
            return true;
        } catch {
            clearTimeout(timeoutId);
            return false;
        }
    },

    async checkIServ() {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), this.PING_TIMEOUT);

        try {
            const response = await fetch('/api/iserv/ping', {
                method: 'HEAD',
                signal: controller.signal,
                cache: 'no-store'
            });
            clearTimeout(timeoutId);
            return response.ok;
        } catch {
            clearTimeout(timeoutId);
            return false;
        }
    },

    shouldCallExternalAPI() {
        return this.state.internetAvailable === true;
    },

    shouldCallIServ() {
        return this.state.iservAvailable === true;
    },

    isOffline() {
        if (navigator.onLine) return false;
        return true;
    },

    async refresh() {
        this.state.lastCheck = null;
        return this.checkConnectivity();
    },

    getStatusText() {
        if (this.isOffline()) {
            return 'Offline';
        } else if (this.state.internetAvailable) {
            return 'Online';
        }
        return 'Verbindung wird geprüft...';
    }
};

if (typeof module !== 'undefined' && module.exports) {
    module.exports = AppConnection;
}
