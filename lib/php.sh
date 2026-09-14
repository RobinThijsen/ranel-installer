#!/usr/bin/env bash
# lib/php.sh

setup_panel_php_pool() {
  local pool_file="/etc/php/8.4/fpm/pool.d/panel.conf"

  log_info "Writing dedicated PHP-FPM pool for 'panel' at ${pool_file}"
  cat > "$pool_file" <<'EOF'
[panel]
user = panel
group = panel
listen = /run/php/php8.4-fpm-panel.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = ondemand
pm.max_children = 5
pm.process_idle_timeout = 10s
EOF

  if command -v php-fpm8.4 >/dev/null 2>&1; then
    php-fpm8.4 -t
  fi

  systemctl reload php8.4-fpm
  log_info "Reloaded php8.4-fpm with the 'panel' pool active"
}
