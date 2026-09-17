setup() {
  export PANEL_LOG_FILE="$BATS_TEST_TMPDIR/install.log"
  source "$BATS_TEST_DIRNAME/../../lib/log.sh"
  source "$BATS_TEST_DIRNAME/../../lib/logrotate.sh"
}

@test "render_panel_logrotate rotates the queue, scheduler and panel fpm logs daily with copytruncate" {
  run render_panel_logrotate "8.4"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/var/log/panel-queue.log /var/log/panel-scheduler.log /var/log/php8.4-fpm-panel.log {"* ]]
  [[ "$output" == *"daily"* ]]
  [[ "$output" == *"rotate 14"* ]]
  [[ "$output" == *"copytruncate"* ]]
}

@test "setup_panel_logrotate writes the file and logs it" {
  local target="$BATS_TEST_TMPDIR/ranel-panel"
  run setup_panel_logrotate "8.4" "$target"
  [ "$status" -eq 0 ]
  [ -f "$target" ]
  grep -q "copytruncate" "$target"
  grep -q "Panel log rotation installed" "$PANEL_LOG_FILE"
}
