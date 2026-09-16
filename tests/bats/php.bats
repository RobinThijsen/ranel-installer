setup() {
  export PANEL_LOG_FILE="$BATS_TEST_TMPDIR/install.log"
  source "$BATS_TEST_DIRNAME/../../lib/log.sh"
  source "$BATS_TEST_DIRNAME/../../lib/php.sh"
}

@test "render_panel_pool runs as panel on the socket nginx expects" {
  run render_panel_pool
  [ "$status" -eq 0 ]
  [[ "$output" == *"[panel]"* ]]
  [[ "$output" == *"user = panel"* ]]
  [[ "$output" == *"listen = /run/php/php8.4-fpm-panel.sock"* ]]
  [[ "$output" == *"listen.owner = www-data"* ]]
}

@test "render_panel_fpm_config is a standalone instance including its own pool.d" {
  run render_panel_fpm_config "/etc/php/8.4/fpm/panel"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[global]"* ]]
  [[ "$output" == *"pid = /run/php/php8.4-fpm-panel.pid"* ]]
  [[ "$output" == *"include = /etc/php/8.4/fpm/panel/pool.d/*.conf"* ]]
}

@test "render_panel_fpm_service runs php-fpm on the dedicated config without ProtectSystem" {
  run render_panel_fpm_service "/etc/php/8.4/fpm/panel/php-fpm.conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ExecStart=/usr/sbin/php-fpm8.4 --nodaemonize --fpm-config /etc/php/8.4/fpm/panel/php-fpm.conf"* ]]
  [[ "$output" == *"Type=notify"* ]]
  [[ "$output" == *"Restart=always"* ]]
  [[ "$output" != *"ProtectSystem="* ]]
}

@test "setup_panel_php_pool writes config, pool and unit into the given locations" {
  export PATH="$BATS_TEST_DIRNAME/../fixtures/fake-nginx-bin:$PATH"
  local conf_dir="$BATS_TEST_TMPDIR/panel"
  local unit_file="$BATS_TEST_TMPDIR/panel-fpm.service"

  run setup_panel_php_pool "$conf_dir" "$unit_file"
  [ "$status" -eq 0 ]

  [ -f "$conf_dir/php-fpm.conf" ]
  [ -f "$conf_dir/pool.d/panel.conf" ]
  [ -f "$unit_file" ]
  grep -q "^user = panel$" "$conf_dir/pool.d/panel.conf"
  grep -q "^include = $conf_dir/pool.d/\*.conf$" "$conf_dir/php-fpm.conf"
  grep -q "fpm-config $conf_dir/php-fpm.conf" "$unit_file"
}
