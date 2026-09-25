#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BRAND_NAME="$(sed -n 's/.*"name": *"\([^"]*\)".*/\1/p' "$SCRIPT_DIR/brand/brand.json")"
BRAND_UPPER="$(printf '%s' "$BRAND_NAME" | tr '[:lower:]' '[:upper:]')"
APP_DIR="$SCRIPT_DIR/app"
VENV_DIR="$SCRIPT_DIR/venv"
DATA_DIR="$SCRIPT_DIR/data"

CHECKS_PASSED=0
CHECKS_TOTAL=0
INSTALLS_DONE=0

print_header() {
    echo ""
    echo -e "${PURPLE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    printf "║               🚀 %s - SETUP%*s║\n" "$BRAND_UPPER" $((35 - ${#BRAND_UPPER})) ""
    echo "║                                                              ║"
    echo "║        Automatische Installation aller Komponenten          ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_section() {
    echo ""
    echo -e "${CYAN}${BOLD}━━━ $1 ━━━${NC}"
    echo ""
}

print_check() {
    echo -e "  ${BLUE}[CHECK]${NC} $1"
}

print_ok() {
    echo -e "  ${GREEN}[  OK ]${NC} $1"
    ((CHECKS_PASSED++))
}

print_install() {
    echo -e "  ${YELLOW}[INST.]${NC} $1"
    ((INSTALLS_DONE++))
}

print_skip() {
    echo -e "  ${GREEN}[SKIP ]${NC} $1 (bereits installiert)"
}

print_warn() {
    echo -e "  ${YELLOW}[WARN ]${NC} $1"
}

print_error() {
    echo -e "  ${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "  ${BLUE}[INFO ]${NC} $1"
}

command_exists() {
    command -v "$1" &> /dev/null
}

print_header

echo -e "${BOLD}Willkommen zum ${BRAND_NAME} Setup!${NC}"
echo ""
echo "Dieses Script prüft automatisch, was installiert werden muss"
echo "und führt alle notwendigen Installationen durch."
echo ""
read -p "Drücke Enter um zu starten (oder Ctrl+C zum Abbrechen)..."

print_section "1/5 - System-Anforderungen prüfen"

print_check "Python 3..."
((CHECKS_TOTAL++))
if command_exists python3; then
    PYTHON_VERSION=$(python3 --version 2>&1 | cut -d' ' -f2)
    print_ok "Python $PYTHON_VERSION gefunden"
else
    print_error "Python 3 nicht gefunden!"
    echo ""
    echo -e "  ${BOLD}Installation:${NC}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "    macOS: brew install python3"
        echo "    Oder: https://www.python.org/downloads/"
    else
        echo "    Linux: sudo apt install python3 python3-pip python3-venv"
        echo "    Oder: https://www.python.org/downloads/"
    fi
    echo ""
    exit 1
fi

print_check "pip..."
((CHECKS_TOTAL++))
if python3 -m pip --version &> /dev/null; then
    print_ok "pip verfügbar"
else
    print_install "pip wird installiert..."
    python3 -m ensurepip --upgrade
    print_ok "pip installiert"
fi

if [[ "$OSTYPE" == "darwin"* ]]; then
    print_check "Homebrew (macOS)..."
    ((CHECKS_TOTAL++))
    if command_exists brew; then
        print_ok "Homebrew gefunden"
        HAS_BREW=true
    else
        print_warn "Homebrew nicht gefunden (optional)"
        HAS_BREW=false
    fi
fi

print_section "2/5 - Python Virtual Environment"

print_check "Virtual Environment..."
((CHECKS_TOTAL++))
if [ -d "$VENV_DIR" ] && [ -f "$VENV_DIR/bin/activate" ]; then
    print_skip "Virtual Environment"
else
    print_install "Virtual Environment wird erstellt..."
    python3 -m venv "$VENV_DIR"
    print_ok "Virtual Environment erstellt"
fi

source "$VENV_DIR/bin/activate"
print_ok "Virtual Environment aktiviert"

print_check "pip aktualisieren..."
pip install --quiet --upgrade pip

print_section "3/5 - Python Pakete installieren"

install_if_missing() {
    local package=$1
    local pip_name=${2:-$1}

    print_check "$package..."
    ((CHECKS_TOTAL++))

    if pip show "$package" &> /dev/null; then
        print_skip "$package"
    else
        print_install "$package wird installiert..."
        pip install --quiet "$pip_name"
        print_ok "$package installiert"
    fi
}

install_if_missing "flask" "flask>=3.0.0"
install_if_missing "flask-cors" "flask-cors>=4.0.0"
install_if_missing "flask-socketio" "flask-socketio>=5.3.0"
install_if_missing "flask-login" "flask-login>=0.6.0"

install_if_missing "gunicorn" "gunicorn>=21.0.0"
install_if_missing "gevent" "gevent>=23.0.0"
install_if_missing "gevent-websocket" "gevent-websocket>=0.10.0"

install_if_missing "psycopg2-binary" "psycopg2-binary>=2.9.0"

install_if_missing "google-api-python-client" "google-api-python-client>=2.100.0"
install_if_missing "google-auth" "google-auth>=2.23.0"
install_if_missing "google-auth-oauthlib" "google-auth-oauthlib>=1.1.0"
install_if_missing "google-auth-httplib2" "google-auth-httplib2>=0.1.0"

install_if_missing "python-dotenv" "python-dotenv>=1.0.0"
install_if_missing "requests" "requests>=2.31.0"

install_if_missing "beautifulsoup4" "beautifulsoup4"
install_if_missing "IServAPI" "IServAPI"

print_section "4/5 - Konfiguration"

print_check "Data Verzeichnis..."
((CHECKS_TOTAL++))
if [ -d "$DATA_DIR" ]; then
    print_skip "Data Verzeichnis"
else
    print_install "Data Verzeichnis wird erstellt..."
    mkdir -p "$DATA_DIR"
    print_ok "Data Verzeichnis erstellt"
fi

print_check ".env Konfiguration..."
((CHECKS_TOTAL++))
if [ -f "$SCRIPT_DIR/.env" ]; then
    print_skip ".env Datei"
else
    if [ -f "$SCRIPT_DIR/.env.example" ]; then
        print_install ".env wird aus Vorlage erstellt..."
        cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
        print_ok ".env erstellt (bitte API-Keys eintragen!)"
        print_warn "Vergiss nicht, deine API-Keys in .env einzutragen!"
    else
        print_install ".env wird erstellt..."
        cat > "$SCRIPT_DIR/.env" << 'EOF'
SECRET_KEY=secret-key-change-me
FLASK_ENV=development

GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
GOOGLE_PROJECT_ID=
EOF
        print_ok ".env erstellt"
    fi
fi

print_section "5/5 - Datenbank initialisieren"

print_check "SQLite Datenbank..."
((CHECKS_TOTAL++))

cd "$SCRIPT_DIR"
print_install "Datenbank wird initialisiert..."
python3 -c "from app import database; print('Database initialized')" 2>/dev/null && print_ok "Datenbank initialisiert" || print_warn "Datenbank-Check übersprungen"

echo ""
echo -e "${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                                                              ║"
echo "║              ✅ SETUP ERFOLGREICH ABGESCHLOSSEN!             ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo ""
echo -e "${BOLD}Zusammenfassung:${NC}"
echo -e "  • Checks bestanden: ${GREEN}$CHECKS_PASSED/$CHECKS_TOTAL${NC}"
echo -e "  • Neue Installationen: ${YELLOW}$INSTALLS_DONE${NC}"
echo ""

echo -e "${BOLD}Nächste Schritte:${NC}"
echo ""
echo "  1. ${BRAND_NAME} starten:"
echo -e "     ${CYAN}./start.sh${NC}"
echo ""
echo "  2. Im Browser öffnen:"
echo -e "     ${CYAN}http://localhost:5050${NC}"
echo ""

if [ ! -s "$SCRIPT_DIR/.env" ] || grep -q "GOOGLE_CLIENT_ID=$" "$SCRIPT_DIR/.env"; then
    echo -e "${YELLOW}${BOLD}Optionale Konfiguration:${NC}"
    echo ""
    echo "  Für Google Kalender & Email Integration:"
    echo "  • Öffne die Datei .env"
    echo "  • Trage deine Google API Credentials ein"
    echo "  • Anleitung: https://console.cloud.google.com/"
    echo ""
fi

echo -e "${BOLD}Viel Spaß mit ${BRAND_NAME}! 🎉${NC}"
echo ""
