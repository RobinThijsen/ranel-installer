#!/usr/bin/env bash
# lib/logrotate.sh
#
# Rotation of the panel's own log files (queue worker, scheduler, the
# panel's PHP-FPM instance) through /etc/logrotate.d/ranel-panel.
# copytruncate: systemd (StandardOutput=append:) and the PHP-FPM master
# keep the file open, a rename would leave them writing into the old one.
# panel-update.sh rewrites the same file on every update. The sites' own
# logs get one file each, written by the panel (site-logrotate.sh).

render_panel_logrotate() {
  local fpm_version="${1:-8.4}"

  cat <<EOF
# managed by ranel — do not edit, rewritten by panel-update.sh
/var/log/panel-queue.log /var/log/panel-scheduler.log /var/log/php${fpm_version}-fpm-panel.log {
    daily
    rotate 14
    missingok
    notifempty
    compress
    delaycompress
    dateext
    copytruncate
}
EOF
}

setup_panel_logrotate() {
  local fpm_version="${1:-8.4}"
  local target="${2:-/etc/logrotate.d/ranel-panel}"

  render_panel_logrotate "$fpm_version" > "$target"
  chmod 644 "$target"
  if [ "$(id -u)" -eq 0 ]; then
    chown root:root "$target"
  fi

  log_info "Panel log rotation installed (${target})"
}
