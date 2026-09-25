#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_NAME="xfce-xrdp"
STATE_DIR="/var/lib/${PROJECT_NAME}"
STATE_FILE="${STATE_DIR}/state.env"
STARTWM="/etc/xrdp/startwm.sh"
BRAVE_KEY="/usr/share/keyrings/brave-browser-archive-keyring.gpg"
BRAVE_SOURCE="/etc/apt/sources.list.d/brave-browser-release.sources"

log() { printf '[%s] %s\n' "$PROJECT_NAME" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$PROJECT_NAME" "$*" >&2; }
die() { printf '[%s] ERROR: %s\n' "$PROJECT_NAME" "$*" >&2; exit 1; }

require_root() {
  [[ ${EUID} -eq 0 ]] || die "Run this installer as root (sudo bash install.sh)."
}

prompt_yes_no() {
  local prompt="$1" default="${2:-Y}" answer
  if [[ "$default" == "Y" ]]; then
    read -r -p "$prompt [Y/n]: " answer || true
    answer=${answer:-Y}
  else
    read -r -p "$prompt [y/N]: " answer || true
    answer=${answer:-N}
  fi
  [[ "$answer" =~ ^[Yy]$ ]]
}

pkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q '^install ok installed$'
}

write_state_var() {
  local key="$1" value="$2"
  printf '%s=%q\n' "$key" "$value" >> "$STATE_FILE"
}

require_root

[[ -r /etc/os-release ]] || die "/etc/os-release is missing."
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || die "This installer currently supports Ubuntu only."
case "${VERSION_ID:-}" in
  22.04|24.04|26.04) ;;
  *) die "Unsupported Ubuntu version: ${VERSION_ID:-unknown}. Supported: 22.04, 24.04, 26.04." ;;
esac

ARCH=$(dpkg --print-architecture)
case "$ARCH" in
  amd64|arm64) ;;
  *) die "Unsupported architecture: $ARCH. Supported: amd64 and arm64." ;;
esac

if [[ -e "$STATE_FILE" ]]; then
  die "An existing ${PROJECT_NAME} installation is already recorded at ${STATE_FILE}. Run uninstall.sh first or inspect that file."
fi

printf '\nXFCE + xRDP Setup\n==================\n'
printf 'Detected: Ubuntu %s (%s)\n' "$VERSION_ID" "$ARCH"
printf 'CPU cores: %s\n' "$(nproc)"
printf 'Memory: %s\n\n' "$(free -h | awk '/^Mem:/ {print $2}')"

read -r -p 'Desktop/RDP username [browser]: ' RDP_USER
RDP_USER=${RDP_USER:-browser}
[[ "$RDP_USER" != "root" ]] || die "The RDP account cannot be root."
[[ "$RDP_USER" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || die "Invalid Linux username: $RDP_USER"

USER_CREATED=0
if id "$RDP_USER" >/dev/null 2>&1; then
  log "User '$RDP_USER' already exists."
  if prompt_yes_no "Reset the password for '$RDP_USER'?" "N"; then
    passwd "$RDP_USER"
  fi
else
  adduser --disabled-password --gecos "" "$RDP_USER"
  USER_CREATED=1
  printf '\nSet the password used to sign in through RDP:\n'
  passwd "$RDP_USER"
fi

RDP_HOME=$(getent passwd "$RDP_USER" | cut -d: -f6)
[[ -n "$RDP_HOME" && -d "$RDP_HOME" ]] || die "Could not determine a valid home directory for $RDP_USER."

INSTALL_BRAVE=0
if prompt_yes_no "Install Brave Origin?" "Y"; then
  INSTALL_BRAVE=1
fi

printf '\nRDP firewall mode:\n'
printf '  1) SSH tunnel only / do not add a TCP 3389 firewall rule (recommended)\n'
printf '  2) Allow TCP 3389 only from one IPv4 address\n'
printf '  3) Allow TCP 3389 publicly\n'
read -r -p 'Choice [1]: ' FIREWALL_MODE
FIREWALL_MODE=${FIREWALL_MODE:-1}
[[ "$FIREWALL_MODE" =~ ^[123]$ ]] || die "Invalid firewall choice."

ALLOWED_IP=""
if [[ "$FIREWALL_MODE" == "2" ]]; then
  read -r -p 'IPv4 address allowed to connect to RDP: ' ALLOWED_IP
  [[ "$ALLOWED_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die "Invalid IPv4 format."
  IFS=. read -r o1 o2 o3 o4 <<< "$ALLOWED_IP"
  for octet in "$o1" "$o2" "$o3" "$o4"; do
    (( octet >= 0 && octet <= 255 )) || die "Invalid IPv4 address."
  done
fi

if ! prompt_yes_no "Proceed with installation?" "Y"; then
  log "Cancelled."
  exit 0
fi

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"
: > "$STATE_FILE"
chmod 600 "$STATE_FILE"
write_state_var RDP_USER "$RDP_USER"
write_state_var RDP_HOME "$RDP_HOME"
write_state_var USER_CREATED "$USER_CREATED"
write_state_var FIREWALL_MODE "$FIREWALL_MODE"
write_state_var ALLOWED_IP "$ALLOWED_IP"
write_state_var BRAVE_REQUESTED "$INSTALL_BRAVE"

PACKAGES=(xfce4 xfce4-terminal xrdp xorgxrdp dbus-x11)
UTILITY_PACKAGES=(curl ca-certificates)
NEW_PACKAGES=()
for pkg in "${PACKAGES[@]}"; do
  if ! pkg_installed "$pkg"; then
    NEW_PACKAGES+=("$pkg")
  fi
done
write_state_var NEW_PACKAGES "${NEW_PACKAGES[*]}"

XRDP_WAS_ACTIVE=0
if systemctl is-active --quiet xrdp 2>/dev/null; then
  XRDP_WAS_ACTIVE=1
fi
write_state_var XRDP_WAS_ACTIVE "$XRDP_WAS_ACTIVE"

log "Updating APT metadata..."
apt-get update
log "Installing XFCE and xRDP..."
DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y "${PACKAGES[@]}" "${UTILITY_PACKAGES[@]}"

BRAVE_NEWLY_INSTALLED=0
BRAVE_REPO_CREATED=0
if [[ "$INSTALL_BRAVE" == "1" ]]; then
  if ! pkg_installed brave-origin; then
    BRAVE_NEWLY_INSTALLED=1
  fi
  if [[ ! -e "$BRAVE_SOURCE" ]]; then
    BRAVE_REPO_CREATED=1
  fi
  log "Configuring the official Brave repository..."
  curl -fsSLo "$BRAVE_KEY" https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
  curl -fsSLo "$BRAVE_SOURCE" https://brave-browser-apt-release.s3.brave.com/brave-browser.sources
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y brave-origin
fi
write_state_var BRAVE_NEWLY_INSTALLED "$BRAVE_NEWLY_INSTALLED"
write_state_var BRAVE_REPO_CREATED "$BRAVE_REPO_CREATED"

if [[ -f "$STARTWM" ]]; then
  cp -a "$STARTWM" "${STATE_DIR}/startwm.sh.backup"
  write_state_var STARTWM_BACKED_UP "1"
else
  write_state_var STARTWM_BACKED_UP "0"
fi

cat > "$STARTWM" <<'EOF_STARTWM'
#!/bin/sh
unset DBUS_SESSION_BUS_ADDRESS
unset SESSION_MANAGER
exec dbus-run-session -- startxfce4
EOF_STARTWM
chmod 755 "$STARTWM"

cat > "${RDP_HOME}/.xsession" <<'EOF_XSESSION'
#!/bin/sh
unset DBUS_SESSION_BUS_ADDRESS
unset SESSION_MANAGER
exec dbus-run-session -- startxfce4
EOF_XSESSION
chown "$RDP_USER:$RDP_USER" "${RDP_HOME}/.xsession"
chmod 755 "${RDP_HOME}/.xsession"

XFWM_DIR="${RDP_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml"
mkdir -p "$XFWM_DIR"
if [[ -e "${XFWM_DIR}/xfwm4.xml" ]]; then
  cp -a "${XFWM_DIR}/xfwm4.xml" "${STATE_DIR}/xfwm4.xml.backup"
  write_state_var XFWM4_BACKED_UP "1"
else
  write_state_var XFWM4_BACKED_UP "0"
fi
cat > "${XFWM_DIR}/xfwm4.xml" <<'EOF_XFWM'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="false"/>
  </property>
</channel>
EOF_XFWM
chown -R "$RDP_USER:$RDP_USER" "${RDP_HOME}/.config"

if getent group ssl-cert >/dev/null 2>&1; then
  usermod -aG ssl-cert xrdp
fi

UFW_RULE_ADDED=0
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
  case "$FIREWALL_MODE" in
    1)
      log "UFW is active; TCP 3389 remains closed to new public connections."
      ;;
    2)
      ufw allow from "$ALLOWED_IP" to any port 3389 proto tcp comment 'xfce-xrdp' >/dev/null
      UFW_RULE_ADDED=1
      ;;
    3)
      warn "Opening TCP 3389 to the public Internet. Restrict this at UFW/provider firewall when possible."
      ufw allow 3389/tcp comment 'xfce-xrdp' >/dev/null
      UFW_RULE_ADDED=1
      ;;
  esac
else
  if [[ "$FIREWALL_MODE" != "1" ]]; then
    warn "UFW is not active. No host-firewall rule was added. Check your VPS provider firewall separately."
  fi
fi
write_state_var UFW_RULE_ADDED "$UFW_RULE_ADDED"

systemctl enable xrdp >/dev/null
systemctl restart xrdp-sesman
systemctl restart xrdp

if ! systemctl is-active --quiet xrdp; then
  die "xRDP did not start successfully. Check: systemctl status xrdp --no-pager"
fi
if ! ss -ltn | awk '{print $4}' | grep -Eq '(^|:)3389$'; then
  warn "xRDP is active, but TCP 3389 was not detected as listening."
fi

SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')

printf '\n=================================================\n'
printf ' XFCE + xRDP installation complete\n'
printf '=================================================\n'
printf 'Username:      %s\n' "$RDP_USER"
printf 'Desktop:       XFCE\n'
printf 'RDP service:   active\n'
printf 'RDP port:      3389\n'
if [[ "$INSTALL_BRAVE" == "1" ]]; then
  printf 'Browser:       Brave Origin\n'
fi
printf '\n'
case "$FIREWALL_MODE" in
  1)
    printf 'RDP exposure:  No UFW rule added (SSH tunnel recommended)\n'
    printf 'Example tunnel from your computer:\n'
    printf '  ssh -L 13389:127.0.0.1:3389 root@YOUR_SERVER_IP\n'
    printf 'Then connect RDP to: 127.0.0.1:13389\n'
    ;;
  2)
    printf 'RDP exposure:  Restricted to %s when UFW is active\n' "$ALLOWED_IP"
    printf 'Connect to:    %s\n' "${SERVER_IP:-YOUR_SERVER_IP}"
    ;;
  3)
    printf 'RDP exposure:  Public when permitted by host/provider firewall\n'
    printf 'Connect to:    %s\n' "${SERVER_IP:-YOUR_SERVER_IP}"
    ;;
esac
printf '\nChoose the Xorg session at the xRDP login screen.\n'
printf 'State/rollback data: %s\n' "$STATE_DIR"
printf '=================================================\n'
