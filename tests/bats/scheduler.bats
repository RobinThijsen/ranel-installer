setup() {
  export PANEL_LOG_FILE="$BATS_TEST_TMPDIR/install.log"
  source "$BATS_TEST_DIRNAME/../../lib/log.sh"
  source "$BATS_TEST_DIRNAME/../../lib/scheduler.sh"
}

@test "render_scheduler_cron runs schedule:run every minute as panel from the app dir with a log" {
  run render_scheduler_cron "/opt/panel/app" "/var/log/panel-scheduler.log"

  [ "$status" -eq 0 ]
  [[ "$output" == *'MAILTO=""'* ]]
  [[ "$output" == *"* * * * * panel cd /opt/panel/app && HOME=/var/lib/panel php artisan schedule:run >> /var/log/panel-scheduler.log 2>&1"* ]]
  [[ "$output" == *"managed by ranel"* ]]
}

@test "setup_scheduler writes the cron file, creates the log file and keeps an existing one" {
  local cron_file="$BATS_TEST_TMPDIR/panel"
  local log_file="$BATS_TEST_TMPDIR/panel-scheduler.log"

  run setup_scheduler "/opt/panel/app" "$cron_file" "$log_file"
  [ "$status" -eq 0 ]
  [ -f "$cron_file" ]
  grep -q "schedule:run >> $log_file" "$cron_file"
  [ -f "$log_file" ]
  grep -q "Scheduler installed" "$PANEL_LOG_FILE"

  echo "kept" > "$log_file"
  run setup_scheduler "/opt/panel/app" "$cron_file" "$log_file"
  [ "$status" -eq 0 ]
  [ "$(cat "$log_file")" = "kept" ]
}
