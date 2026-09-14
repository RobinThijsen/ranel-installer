setup() {
  export PANEL_LOG_FILE="$BATS_TEST_TMPDIR/install.log"
  source "$BATS_TEST_DIRNAME/../../lib/log.sh"
}

@test "log_info writes an INFO line with the message" {
  log_info "starting step"
  run cat "$PANEL_LOG_FILE"
  [[ "$output" == *"INFO"* ]]
  [[ "$output" == *"starting step"* ]]
}

@test "log_error writes an ERROR line with the message" {
  log_error "something broke"
  run cat "$PANEL_LOG_FILE"
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" == *"something broke"* ]]
}
