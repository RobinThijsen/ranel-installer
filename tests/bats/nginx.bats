setup() {
  export PANEL_LOG_FILE="$BATS_TEST_TMPDIR/install.log"
  source "$BATS_TEST_DIRNAME/../../lib/log.sh"
  source "$BATS_TEST_DIRNAME/../../lib/nginx.sh"
}

@test "render_panel_vhost points server_name and root at the given domain and app" {
  run render_panel_vhost "panel.example.com" "/opt/panel/app"

  [ "$status" -eq 0 ]
  [[ "$output" == *"server_name panel.example.com;"* ]]
  [[ "$output" == *"root /opt/panel/app/public;"* ]]
  [[ "$output" == *"fastcgi_pass unix:/run/php/php8.4-fpm-panel.sock;"* ]]
}

@test "write_panel_vhost writes the vhost file and enables it via symlink" {
  export PATH="$BATS_TEST_DIRNAME/../fixtures/fake-nginx-bin:$PATH"
  local sites_available="$BATS_TEST_TMPDIR/sites-available"
  local sites_enabled="$BATS_TEST_TMPDIR/sites-enabled"
  mkdir -p "$sites_available" "$sites_enabled"

  run write_panel_vhost "panel.example.com" "/opt/panel/app" "$sites_available" "$sites_enabled"
  [ "$status" -eq 0 ]

  [ -f "$sites_available/panel.conf" ]
  run cat "$sites_available/panel.conf"
  [[ "$output" == *"server_name panel.example.com;"* ]]
  [[ "$output" == *"root /opt/panel/app/public;"* ]]

  [ -L "$sites_enabled/panel.conf" ]
}
