#!/usr/bin/env bash
# lib/php.sh
#
# The panel gets its own PHP-FPM *instance* (panel-fpm.service), not just a
# pool inside php8.4-fpm.service: Debian/Ubuntu ship php-fpm with
# ProtectSystem=full, which makes /etc read-only for every process it
# spawns — including the privileged scripts the panel runs through sudo
# (useradd, nginx vhosts, FPM pools all write under /etc). Found on the
# first real VM test. Site pools stay in the hardened system instance.

PANEL_FPM_VERSION="8.4"
PANEL_FPM_CONF_DIR="/etc/php/${PANEL_FPM_VERSION}/fpm/panel"
PANEL_FPM_SOCKET="/run/php/php${PANEL_FPM_VERSION}-fpm-panel.sock"

render_panel_pool() {
  cat <<EOF
[panel]
user = panel
group = panel
listen = ${PANEL_FPM_SOCKET}
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = ondemand
pm.max_children = 5
pm.process_idle_timeout = 10s
EOF
}

render_panel_fpm_config() {
  local conf_dir="$1"

  cat <<EOF
; Dedicated PHP-FPM instance for the panel (see lib/php.sh in ranel-installer).
[global]
pid = /run/php/php${PANEL_FPM_VERSION}-fpm-panel.pid
error_log = /var/log/php${PANEL_FPM_VERSION}-fpm-panel.log
include = ${conf_dir}/pool.d/*.conf
EOF
}

render_panel_fpm_service() {
  local conf_file="$1"

  cat <<EOF
[Unit]
Description=Ranel panel PHP-FPM (dedicated instance)
# No ProtectSystem here on purpose: this instance runs the panel, which
# calls the privileged scripts in /opt/panel/scripts through sudo, and
# those scripts write under /etc.
After=network.target

[Service]
Type=notify
ExecStart=/usr/sbin/php-fpm${PANEL_FPM_VERSION} --nodaemonize --fpm-config ${conf_file}
ExecReload=/bin/kill -USR2 \$MAINPID
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

setup_panel_php_pool() {
  local conf_dir="${1:-$PANEL_FPM_CONF_DIR}"
  local unit_file="${2:-/etc/systemd/system/panel-fpm.service}"
  local conf_file="${conf_dir}/php-fpm.conf"

  mkdir -p "${conf_dir}/pool.d"
  render_panel_fpm_config "$conf_dir" > "$conf_file"
  render_panel_pool > "${conf_dir}/pool.d/panel.conf"
  render_panel_fpm_service "$conf_file" > "$unit_file"
  chmod 644 "$unit_file"
  log_info "Wrote dedicated PHP-FPM instance config for 'panel' at ${conf_file}"

  # A leftover panel pool in the system instance (older layout) would fight
  # for the same socket.
  if [ -f "/etc/php/${PANEL_FPM_VERSION}/fpm/pool.d/panel.conf" ]; then
    rm -f "/etc/php/${PANEL_FPM_VERSION}/fpm/pool.d/panel.conf"
    systemctl reload "php${PANEL_FPM_VERSION}-fpm" || true
    log_info "Removed the old 'panel' pool from the system php-fpm instance"
  fi

  if command -v "php-fpm${PANEL_FPM_VERSION}" >/dev/null 2>&1; then
    "php-fpm${PANEL_FPM_VERSION}" -t --fpm-config "$conf_file"
  fi

  systemctl daemon-reload
  systemctl enable --now panel-fpm
  systemctl restart panel-fpm
  log_info "panel-fpm started (socket ${PANEL_FPM_SOCKET})"
}
