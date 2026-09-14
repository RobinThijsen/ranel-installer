#!/usr/bin/env bash
# lib/user.sh

create_panel_user() {
  if id panel >/dev/null 2>&1; then
    log_info "System user 'panel' already exists, skipping creation"
    return 0
  fi

  useradd --system --shell /usr/sbin/nologin --home-dir /opt/panel --create-home panel
  log_info "Created system user 'panel' (nologin)"
}
