setup() {
  source "$BATS_TEST_DIRNAME/../../lib/log.sh"
  source "$BATS_TEST_DIRNAME/../../lib/gate.sh"
  export PANEL_LOG_FILE="$BATS_TEST_TMPDIR/install.log"
  export PATH="$BATS_TEST_DIRNAME/../fixtures/fake-git-bin:$PATH"
}

@test "validate_git_key succeeds with a valid key" {
  run validate_git_key "git@example.com:agency/panel-app.git" "/tmp/valid-key"
  [ "$status" -eq 0 ]
}

@test "validate_git_key fails with an invalid key and logs an error" {
  run validate_git_key "git@example.com:agency/panel-app.git" "/tmp/bad-key"
  [ "$status" -ne 0 ]
  run cat "$PANEL_LOG_FILE"
  [[ "$output" == *"ERROR"* ]]
}
