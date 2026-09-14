setup() {
  export PANEL_LOG_FILE="$BATS_TEST_TMPDIR/install.log"
  source "$BATS_TEST_DIRNAME/../../lib/log.sh"
  source "$BATS_TEST_DIRNAME/../../lib/scripts_dir.sh"
}

@test "render_sudoers_line produces an exact-path NOPASSWD entry" {
  run render_sudoers_line "/opt/panel/scripts/create-site.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "panel ALL=(root) NOPASSWD: /opt/panel/scripts/create-site.sh" ]
}

@test "add_sudoers_entry appends the line and validates syntax" {
  local sudoers_file="$BATS_TEST_TMPDIR/sudoers.d-panel"
  : > "$sudoers_file"
  run add_sudoers_entry "/opt/panel/scripts/create-site.sh" "$sudoers_file"
  [ "$status" -eq 0 ]
  run cat "$sudoers_file"
  [[ "$output" == *"/opt/panel/scripts/create-site.sh"* ]]
}
