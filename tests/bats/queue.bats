setup() {
  export PANEL_LOG_FILE="$BATS_TEST_TMPDIR/install.log"
  source "$BATS_TEST_DIRNAME/../../lib/log.sh"
  source "$BATS_TEST_DIRNAME/../../lib/queue.sh"
}

@test "render_queue_service runs queue:work as panel from the app dir and restarts on failure" {
  run render_queue_service "/opt/panel/app"

  [ "$status" -eq 0 ]
  [[ "$output" == *"User=panel"* ]]
  [[ "$output" == *"WorkingDirectory=/opt/panel/app"* ]]
  [[ "$output" == *"ExecStart=/usr/bin/php /opt/panel/app/artisan queue:work database --sleep=3 --tries=1 --timeout=7320 --max-time=3600"* ]]
  [[ "$output" == *"Restart=always"* ]]
  [[ "$output" == *"WantedBy=multi-user.target"* ]]
}

@test "setup_queue_worker writes the unit file, reloads systemd and enables the service" {
  export PATH="$BATS_TEST_DIRNAME/../fixtures/fake-nginx-bin:$PATH"
  local unit_file="$BATS_TEST_TMPDIR/panel-queue.service"

  run setup_queue_worker "/opt/panel/app" "$unit_file"
  [ "$status" -eq 0 ]

  [ -f "$unit_file" ]
  run cat "$unit_file"
  [[ "$output" == *"queue:work database"* ]]
}
