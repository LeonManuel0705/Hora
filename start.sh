#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BRAND_NAME="$(sed -n 's/.*"name": *"\([^"]*\)".*/\1/p' "$SCRIPT_DIR/brand/brand.json")"
BRAND_UPPER="$(printf '%s' "$BRAND_NAME" | tr '[:lower:]' '[:upper:]')"
APP_DIR="$SCRIPT_DIR/app"
VENV_DIR="$SCRIPT_DIR/venv"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

echo ""
echo -e "${CYAN}${BOLD}"
echo "╔════════════════════════════════════════════╗"
printf "║%*s%s%*s║\n" $(( (44 - ${#BRAND_UPPER}) / 2 )) "" "$BRAND_UPPER" $(( 44 - ${#BRAND_UPPER} - (44 - ${#BRAND_UPPER}) / 2 )) ""
echo "║            Dein persönlicher Hub           ║"
echo "║               Developer: Leon              ║"
echo "╚════════════════════════════════════════════╝"
echo -e "${NC}"

if [ ! -d "$VENV_DIR" ]; then
    echo -e "${YELLOW}${BRAND_NAME} ist noch nicht eingerichtet!${NC}"
    echo ""
    echo "   Bitte führe zuerst das Setup aus:"
    echo -e "   ${CYAN}./setup.sh${NC}"
    echo ""
    exit 1
fi

source "$VENV_DIR/bin/activate"

pip install --quiet -r "$SCRIPT_DIR/requirements.txt" 2>/dev/null

LOCAL_IP=$(python3 -c "import socket; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.connect(('8.8.8.8',80)); print(s.getsockname()[0]); s.close()" 2>/dev/null)

echo -e "🚀 ${BOLD}Server wird gestartet...${NC}"
echo ""

echo -e "   ${BOLD}Desktop:${NC}  ${GREEN}http://localhost:5050${NC}"
if [ -n "$LOCAL_IP" ]; then
    echo -e "   ${BOLD}Mobile:${NC}   ${GREEN}http://${LOCAL_IP}:5050${NC}"
    echo ""
    echo -e "   📱 ${CYAN}Auf Android/iOS: URL im Browser eingeben${NC}"
    echo -e "      ${CYAN}und 'Zum Home-Bildschirm hinzufügen'${NC}"
fi
echo ""
echo -e "   ${YELLOW}Ctrl+C${NC} zum Beenden"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

(sleep 2 && open "http://localhost:5050" 2>/dev/null) &

cd "$SCRIPT_DIR"
python3 -m app.app
