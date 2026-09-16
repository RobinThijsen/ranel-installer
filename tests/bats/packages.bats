setup() {
  export PANEL_LOG_FILE="$BATS_TEST_TMPDIR/install.log"
  source "$BATS_TEST_DIRNAME/../../lib/log.sh"
  source "$BATS_TEST_DIRNAME/../../lib/packages.sh"
  export PATH="$BATS_TEST_DIRNAME/../fixtures/fake-apt-bin:$PATH"
  export FAKE_CALLS_LOG="$BATS_TEST_TMPDIR/calls.log"; : > "$FAKE_CALLS_LOG"
}

@test "apply_package_manifest installs only the missing packages and ignores comments" {
  printf '# runtime packages\nphp8.4-gd\nphp8.4-bcmath   # money\n\nunzip\n' > "$BATS_TEST_TMPDIR/packages.txt"
  export FAKE_INSTALLED_PKGS="unzip"

  run apply_package_manifest "$BATS_TEST_TMPDIR/packages.txt"
  [ "$status" -eq 0 ]
  grep -q "^apt-get install -y php8.4-gd php8.4-bcmath$" "$FAKE_CALLS_LOG"
}

@test "apply_package_manifest is a no-op when everything is installed or the manifest is absent" {
  printf 'unzip\n' > "$BATS_TEST_TMPDIR/packages.txt"
  export FAKE_INSTALLED_PKGS="unzip"
  run apply_package_manifest "$BATS_TEST_TMPDIR/packages.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]

  run apply_package_manifest "$BATS_TEST_TMPDIR/missing.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping"* ]]
  ! grep -q "apt-get" "$FAKE_CALLS_LOG"
}
