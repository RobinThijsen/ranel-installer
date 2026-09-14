setup() {
  source "$BATS_TEST_DIRNAME/../../lib/nginx.sh"
}

@test "render_panel_vhost points server_name and root at the given domain and app" {
  run render_panel_vhost "panel.example.com" "/opt/panel/app"

  [ "$status" -eq 0 ]
  [[ "$output" == *"server_name panel.example.com;"* ]]
  [[ "$output" == *"root /opt/panel/app/public;"* ]]
  [[ "$output" == *"fastcgi_pass unix:/run/php/php8.4-fpm.sock;"* ]]
}
