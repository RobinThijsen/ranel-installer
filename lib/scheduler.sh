#!/usr/bin/env bash
# lib/scheduler.sh
#
# Laravel scheduler for the panel app: `php artisan schedule:run` every
# minute as the `panel` user, from /etc/cron.d/panel (root-owned, so the
# panel cannot change what runs). The app schedules its own recurring
# work there (nightly site backups). The log file belongs to panel so
# cron can append to it. panel-update.sh rewrites the same file on every
# update, with the same content.

render_scheduler_cron() {
  local app_dir="$1"
  local log_file="${2:-/var/log/panel-scheduler.log}"

  cat <<EOF
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin
MAILTO=""
# managed by ranel — do not edit, rewritten by panel-update.sh
* * * * * panel cd ${app_dir} && HOME=/var/lib/panel php artisan schedule:run >> ${log_file} 2>&1
EOF
}

setup_scheduler() {
  local app_dir="$1"
  local cron_file="${2:-/etc/cron.d/panel}"
  local log_file="${3:-/var/log/panel-scheduler.log}"

  render_scheduler_cron "$app_dir" "$log_file" > "$cron_file"
  chmod 644 "$cron_file"

  if [ ! -e "$log_file" ]; then
    : > "$log_file"
  fi
  chmod 640 "$log_file"
  if [ "$(id -u)" -eq 0 ]; then
    chown root:root "$cron_file"
    chown panel:panel "$log_file"
  fi

  log_info "Scheduler installed (${cron_file}, log in ${log_file})"
}
