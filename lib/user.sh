#!/usr/bin/env bash
# lib/user.sh

create_panel_user() {
  if id panel >/dev/null 2>&1; then
    log_info "System user 'panel' already exists, skipping creation"
    return 0
  fi

  mkdir -p /opt/panel
  chown root:root /opt/panel
  chmod 755 /opt/panel
  log_info "Created /opt/panel (root:root, 755) before user creation so 'panel' never owns its own parent directory"

  useradd --system --shell /usr/sbin/nologin --home-dir /opt/panel -M panel
  log_info "Created system user 'panel' (nologin)"
}
