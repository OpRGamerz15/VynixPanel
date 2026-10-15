#!/usr/bin/env bash
# Vynix Hosting Panel - Interactive Setup Script
# Supports Debian/Ubuntu-like systems. Run as root or with sudo.

set -euo pipefail

# Colors (fallback if not supported)
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors)" -ge 8 ]; then
  RED=$(tput setaf 1)
  GREEN=$(tput setaf 2)
  YELLOW=$(tput setaf 3)
  BLUE=$(tput setaf 4)
  RESET=$(tput sgr0)
else
  RED='' GREEN='' YELLOW='' BLUE='' RESET=''
fi

PANEL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="vynix-panel"
PANEL_PORT=6580
ENV_FILE="${PANEL_DIR}/.env"
DB_FILE="${PANEL_DIR}/data/vynix.db"

log() { echo -e "${BLUE}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}[OK]${RESET} $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

check_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    log "Detected OS: $PRETTY_NAME"
    if [[ "$ID" != "debian" && "$ID" != "ubuntu" ]]; then
      warn "This script is primarily tested on Debian/Ubuntu. Other distros may require manual dependency installation."
    fi
  else
    warn "Could not detect OS. Proceed with caution."
  fi
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root (use sudo)."
    exit 1
  fi
}

pause() {
  echo
  read -rp "Press Enter to return to the menu..."
}

main_menu() {
  while true; do
    clear || true
    echo "========================================"
    echo "   Vynix Hosting Panel - Setup Menu"
    echo "========================================"
    echo "1. Install Panel (Port 6580)"
    echo "2. Create New Admin"
    echo "3. Restart Panel"
    echo "4. Update Panel"
    echo "5. Uninstall Panel"
    echo "6. Exit"
    echo "========================================"
    read -rp "Select an option [1-6]: " choice
    case "$choice" in
      1) install_menu ;;
      2) create_admin ;;
      3) restart_panel ;;
      4) update_panel ;;
      5) uninstall_panel ;;
      6) exit 0 ;;
      *) error "Invalid option. Please choose 1-6."; sleep 1 ;;
    esac
  done
}

install_menu() {
  while true; do
    clear || true
    echo "Choose how to access Vynix Hosting Panel"
    echo "1. Use Custom Domain"
    echo "2. Use Port"
    echo "3. Back to Main Menu"
    read -rp "Select an option [1-3]: " sub
    case "$sub" in
      1) install_domain ;;
      2) install_port ;;
      3) return ;;
      *) error "Invalid option."; sleep 1 ;;
    esac
  done
}

install_domain() {
  log "Custom Domain configuration selected."
  read -rp "Enter your desired domain (e.g. panel.example.com): " domain
  if ! echo "$domain" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$'; then
    error "Invalid domain format."
    pause
    return
  fi
  log "DNS records must point to this server before HTTPS can be configured."
  echo "Required: A record for $domain pointing to this server's public IP."
  echo "Optional: AAAA record for IPv6."
  read -rp "Have you configured DNS and is it propagated? (y/N): " dns_ok
  if [[ ! "$dns_ok" =~ ^[Yy]$ ]]; then
    warn "Please configure DNS and retry later. Installation aborted for domain mode."
    pause
    return
  fi
  # Note: Full Let's Encrypt + reverse proxy (Caddy/Nginx) setup would go here.
  # In this environment we document the limitation.
  warn "Full automated HTTPS with Let's Encrypt requires certbot/caddy and open ports 80/443."
  warn "This sandbox/environment may not support certificate issuance. Proceeding with configuration preparation."
  # Continue to common install
  perform_install "domain" "$domain"
}

install_port() {
  log "Direct Port access selected (port 6580)."
  if ss -tuln 2>/dev/null | grep -q ":${PANEL_PORT} " || netstat -tuln 2>/dev/null | grep -q ":${PANEL_PORT} "; then
    error "Port $PANEL_PORT is already in use. Please free it or choose a different setup."
    pause
    return
  fi
  read -rp "Allow access from network (not just localhost)? (y/N): " net
  if [[ "$net" =~ ^[Yy]$ ]]; then
    BIND_ADDR="0.0.0.0"
    warn "WARNING: Direct public HTTP access is not recommended for production. Use a domain with HTTPS."
    echo "You may need to open firewall port $PANEL_PORT (e.g. ufw allow $PANEL_PORT/tcp)."
  else
    BIND_ADDR="127.0.0.1"
  fi
  perform_install "port" "$BIND_ADDR"
}

perform_install() {
  local mode="$1"
  local config_value="$2"
  log "Starting installation in $mode mode..."
  check_os
  require_root

  log "Installing Python dependencies..."
  if ! command -v python3 >/dev/null; then
    apt-get update -qq && apt-get install -y python3 python3-pip || { error "Failed to install Python"; pause; return; }
  fi
  if [ -f requirements.txt ]; then
    pip3 install -r requirements.txt --quiet || { error "Failed to install Python packages"; pause; return; }
  else
    pip3 install flask bcrypt --quiet || { error "Failed to install Python packages"; pause; return; }
  fi

  mkdir -p "${PANEL_DIR}/data" "${PANEL_DIR}/logs" "${PANEL_DIR}/servers"
  cd "$PANEL_DIR"

  # Create .env if not exists
  if [ ! -f "$ENV_FILE" ]; then
    cat > "$ENV_FILE" << EOF
NODE_ENV=production
PANEL_PORT=${PANEL_PORT}
PANEL_BIND=0.0.0.0
DATABASE_URL=sqlite:${DB_FILE}
SESSION_SECRET=$(openssl rand -hex 32)
JWT_SECRET=$(openssl rand -hex 32)
ACCESS_MODE=${mode}
ACCESS_CONFIG=${config_value}
EOF
    success "Created .env configuration."
  else
    log ".env already exists. Preserving it."
  fi

  # Initialize DB
  if [ ! -f "$DB_FILE" ]; then
    touch "$DB_FILE"
    success "Initialized database file."
  fi

  # Create systemd service
  cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=Vynix Hosting Panel
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${PANEL_DIR}
EnvironmentFile=${ENV_FILE}
ExecStart=/usr/bin/python3 backend/server.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}" || true
  systemctl restart "${SERVICE_NAME}" || { error "Failed to start service. Check logs: journalctl -u ${SERVICE_NAME}"; pause; return; }

  sleep 2
  if systemctl is-active --quiet "${SERVICE_NAME}"; then
    success "Panel service is running."
    if [ "$mode" = "port" ]; then
      local ip
      ip=$(hostname -I | awk '{print $1}')
      success "Access URL: http://${ip}:${PANEL_PORT}"
      warn "For production, use a custom domain with HTTPS."
    else
      success "Configured for domain: $config_value (verify HTTPS separately)"
    fi
  else
    error "Service failed to start. Check: journalctl -u ${SERVICE_NAME} -n 50"
  fi
  pause
}

create_admin() {
  log "Create New Admin"
  if [ ! -f "$DB_FILE" ]; then
    error "Database not found. Install the panel first."
    pause
    return
  fi
  read -rp "Admin username: " username
  read -rsp "Admin password: " password
  echo
  read -rsp "Confirm password: " password2
  echo
  if [ "$password" != "$password2" ]; then
    error "Passwords do not match."
    pause
    return
  fi
  if [ ${#password} -lt 8 ]; then
    error "Password must be at least 8 characters."
    pause
    return
  fi
  # Create admin using Python
  python3 - << PY
import sqlite3, bcrypt, os
db_path = "$DB_FILE"
username = "$username"
password = "$password"
conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute("""CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role TEXT DEFAULT 'user',
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
)""")
hashed = bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()
try:
    c.execute("INSERT INTO users (username, password_hash, role) VALUES (?, ?, ?)",
              (username, hashed, "admin"))
    conn.commit()
    print("Admin created successfully.")
except sqlite3.IntegrityError:
    print("Username already exists.")
finally:
    conn.close()
PY
  pause
}

restart_panel() {
  log "Restarting panel services..."
  systemctl restart "${SERVICE_NAME}" && success "Restarted." || error "Restart failed."
  systemctl is-active "${SERVICE_NAME}" && success "Service is active." || error "Service not active."
  pause
}

update_panel() {
  log "Update Panel - checking for updates..."
  warn "In a real deployment, this would pull from a trusted git repository or release."
  warn "Here we reinstall Python dependencies and restart."
  cd "$PANEL_DIR"
  pip3 install flask bcrypt --quiet || warn "pip update had issues."
  systemctl restart "${SERVICE_NAME}" || error "Restart after update failed."
  success "Update procedure completed (limited in this environment)."
  pause
}

uninstall_panel() {
  read -rp "Are you sure you want to uninstall the panel services? (y/N): " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log "Uninstall cancelled."
    pause
    return
  fi
  read -rp "Also delete database and server data? This is irreversible! (y/N): " deldata
  systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
  systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
  systemctl daemon-reload
  if [[ "$deldata" =~ ^[Yy]$ ]]; then
    warn "Deleting data directory..."
    rm -rf "${PANEL_DIR}/data" "${PANEL_DIR}/servers" "${PANEL_DIR}/logs" "$ENV_FILE"
  else
    log "Data preserved."
  fi
  success "Panel services removed."
  pause
}

# Trap Ctrl+C
trap 'echo; warn "Interrupted. Returning to menu if possible."; sleep 1' INT

check_os
main_menu
