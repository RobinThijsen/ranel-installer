#!/usr/bin/env bash
# lib/queue.sh
#
# Queue worker for the panel app: deployments (git clone + build) run in
# the background through Laravel's `database` queue, so a worker has to be
# running as the `panel` user. Installed as a systemd unit that restarts
# on failure and recycles itself every hour (--max-time), which also
# bounds how long a stale copy of the code stays in memory.

render_queue_service() {
  local app_dir="$1"

  cat <<EOF
[Unit]
Description=Ranel panel queue worker
After=network.target mysql.service

[Service]
User=panel
Group=panel
WorkingDirectory=${app_dir}
ExecStart=/usr/bin/php ${app_dir}/artisan queue:work database --sleep=3 --tries=1 --timeout=1860 --max-time=3600
Restart=always
RestartSec=5
StandardOutput=append:/var/log/panel-queue.log
StandardError=append:/var/log/panel-queue.log

[Install]
WantedBy=multi-user.target
EOF
}

setup_queue_worker() {
  local app_dir="$1"
  local unit_file="${2:-/etc/systemd/system/panel-queue.service}"

  render_queue_service "$app_dir" > "$unit_file"
  chmod 644 "$unit_file"

  systemctl daemon-reload
  systemctl enable --now panel-queue
  log_info "Queue worker installed and started (${unit_file})"
}
