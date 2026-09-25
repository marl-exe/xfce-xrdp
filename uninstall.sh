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

[[ ${EUID} -eq 0 ]] || die "Run this uninstaller as root (sudo bash uninstall.sh)."
[[ -r "$STATE_FILE" ]] || die "No installer state found at $STATE_FILE. Refusing to guess what should be removed."
# shellcheck disable=SC1090
source "$STATE_FILE"

printf '\nXFCE + xRDP Uninstall\n=====================\n'
printf 'Recorded RDP user: %s\n\n' "$RDP_USER"
printf '1) Remove xRDP/XFCE components installed by this project\n'
printf '2) Remove Brave Origin only (if installed by this project)\n'
printf '3) Remove everything installed/configured by this project\n'
printf '4) Cancel\n'
read -r -p 'Choice [4]: ' CHOICE
CHOICE=${CHOICE:-4}
[[ "$CHOICE" =~ ^[1234]$ ]] || die "Invalid choice."
[[ "$CHOICE" != "4" ]] || { log "Cancelled."; exit 0; }

remove_ufw_rule() {
  [[ "${UFW_RULE_ADDED:-0}" == "1" ]] || return 0
  command -v ufw >/dev/null 2>&1 || return 0
  local rule
  while true; do
    rule=$(ufw status numbered 2>/dev/null | awk '/# xfce-xrdp/ {gsub(/\[|\]/, "", $1); print $1}' | sort -rn | head -1)
    [[ -n "$rule" ]] || break
    ufw --force delete "$rule" >/dev/null 2>&1 || break
  done
}

remove_brave() {
  if [[ "${BRAVE_NEWLY_INSTALLED:-0}" == "1" ]]; then
    apt-get purge -y brave-origin || true
  else
    log "Brave Origin was not newly installed by this project; leaving the package installed."
  fi
  if [[ "${BRAVE_REPO_CREATED:-0}" == "1" ]]; then
    rm -f "$BRAVE_SOURCE" "$BRAVE_KEY"
    apt-get update || true
  fi
}

remove_desktop_stack() {
  loginctl terminate-user "$RDP_USER" 2>/dev/null || true
  pkill -KILL -u "$RDP_USER" 2>/dev/null || true

  remove_ufw_rule

  if [[ "${STARTWM_BACKED_UP:-0}" == "1" && -f "${STATE_DIR}/startwm.sh.backup" ]]; then
    cp -a "${STATE_DIR}/startwm.sh.backup" "$STARTWM"
  fi

  if [[ "${XFWM4_BACKED_UP:-0}" == "1" && -f "${STATE_DIR}/xfwm4.xml.backup" ]]; then
    mkdir -p "${RDP_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml"
    cp -a "${STATE_DIR}/xfwm4.xml.backup" "${RDP_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
    chown "$RDP_USER:$RDP_USER" "${RDP_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml" 2>/dev/null || true
  else
    rm -f "${RDP_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml" 2>/dev/null || true
  fi
  rm -f "${RDP_HOME}/.xsession" 2>/dev/null || true

  if [[ -n "${NEW_PACKAGES:-}" ]]; then
    # shellcheck disable=SC2206
    local packages=( $NEW_PACKAGES )
    if ((${#packages[@]})); then
      apt-get purge -y "${packages[@]}" || true
    fi
  fi

  if [[ "${XRDP_WAS_ACTIVE:-0}" == "1" ]] && dpkg-query -W xrdp >/dev/null 2>&1; then
    systemctl restart xrdp 2>/dev/null || true
  fi
}

case "$CHOICE" in
  1)
    remove_desktop_stack
    ;;
  2)
    remove_brave
    ;;
  3)
    remove_desktop_stack
    remove_brave
    if [[ "${USER_CREATED:-0}" == "1" ]] && id "$RDP_USER" >/dev/null 2>&1; then
      read -r -p "Delete the installer-created user '$RDP_USER' and its home directory? [y/N]: " DELETE_USER || true
      if [[ "$DELETE_USER" =~ ^[Yy]$ ]]; then
        deluser --remove-home "$RDP_USER" || true
      fi
    fi
    ;;
esac

if [[ "$CHOICE" == "3" ]]; then
  rm -rf "$STATE_DIR"
else
  warn "State data was kept at $STATE_DIR so remaining components can still be identified."
fi

printf '\nRemoval completed.\n'
printf 'For safety, this script does not run apt autoremove automatically.\n'
printf 'Review unused packages yourself before removing them.\n'
