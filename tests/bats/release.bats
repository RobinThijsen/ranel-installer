# Tests for lib/release.sh. Run with: bats tests/bats

setup() {
  export PANEL_LOG_FILE="$BATS_TEST_TMPDIR/install.log"
  source "$BATS_TEST_DIRNAME/../../lib/log.sh"
  source "$BATS_TEST_DIRNAME/../../lib/dist.sh"
  source "$BATS_TEST_DIRNAME/../../lib/release.sh"

  export PANEL_ROOT="$BATS_TEST_TMPDIR/opt-panel"
  # chown needs root; the tests check the layout, not the ownership, which
  # TESTING.md verifies on a real machine.
  export PANEL_OWNER PANEL_GROUP
  PANEL_OWNER="$(id -un)"
  PANEL_GROUP="$(id -gn)"

  mkdir -p "$PANEL_ROOT"
}

# A plausible archive: VERSION, artisan, .env.example and a storage tree.
make_archive() {
  local version="$1"
  local build="$BATS_TEST_TMPDIR/build-${version}"

  mkdir -p "${build}/ranel-${version}/storage/framework/views" \
           "${build}/ranel-${version}/public"
  echo "$version" > "${build}/ranel-${version}/VERSION"
  : > "${build}/ranel-${version}/artisan"
  printf 'APP_URL=http://localhost\nAPP_KEY=\n' > "${build}/ranel-${version}/.env.example"
  echo "marqueur-${version}" > "${build}/ranel-${version}/public/marqueur.txt"
  echo "journal de ${version}" > "${build}/ranel-${version}/storage/logs-temoin.txt"

  tar czf "${BATS_TEST_TMPDIR}/ranel-${version}.tar.gz" -C "$build" "ranel-${version}"
  echo "${BATS_TEST_TMPDIR}/ranel-${version}.tar.gz"
}

@test "a first install lays out releases, shared and the app link" {
  run panel_install_release "1.0.0" "$(make_archive 1.0.0)"
  [ "$status" -eq 0 ]

  [ -f "$PANEL_ROOT/releases/1.0.0/VERSION" ]
  [ -d "$PANEL_ROOT/shared" ]
  # the archive's storage became the shared one, so the framework tree
  # exists without being invented here
  [ -d "$PANEL_ROOT/shared/storage/framework/views" ]
  [ -f "$PANEL_ROOT/shared/storage/logs-temoin.txt" ]
  [ -L "$PANEL_ROOT/releases/1.0.0/storage" ]
  [ -L "$PANEL_ROOT/releases/1.0.0/.env" ]

  run panel_activate_release "1.0.0"
  [ "$status" -eq 0 ]
  [ -L "$PANEL_ROOT/app" ]
  [ "$(readlink "$PANEL_ROOT/app")" = "releases/1.0.0" ]
  [ "$(cat "$PANEL_ROOT/app/VERSION")" = "1.0.0" ]
  [ "$(panel_current_version)" = "1.0.0" ]
}

@test "an update keeps the configuration and the storage of the previous version" {
  panel_install_release "1.0.0" "$(make_archive 1.0.0)"
  panel_activate_release "1.0.0"

  # what the installer renders once, and must survive every update
  printf 'APP_KEY=base64:secret\nDB_PASSWORD=motdepasse\n' > "$PANEL_ROOT/shared/.env"
  echo "une session" > "$PANEL_ROOT/shared/storage/framework/sessions-temoin"

  run panel_install_release "1.0.1" "$(make_archive 1.0.1)"
  [ "$status" -eq 0 ]
  run panel_activate_release "1.0.1"
  [ "$status" -eq 0 ]

  [ "$(panel_current_version)" = "1.0.1" ]
  [ "$(cat "$PANEL_ROOT/app/VERSION")" = "1.0.1" ]
  # the same .env, through the new release's link
  grep -q "^APP_KEY=base64:secret$" "$PANEL_ROOT/app/.env"
  [ -f "$PANEL_ROOT/app/storage/framework/sessions-temoin" ]
  # and the previous release is still there, which is what makes a
  # rollback possible
  [ -f "$PANEL_ROOT/releases/1.0.0/VERSION" ]
}

@test "a rollback is one link away, and serves the previous code" {
  panel_install_release "1.0.0" "$(make_archive 1.0.0)"
  panel_activate_release "1.0.0"
  panel_install_release "1.0.1" "$(make_archive 1.0.1)"
  panel_activate_release "1.0.1"
  [ "$(cat "$PANEL_ROOT/app/public/marqueur.txt")" = "marqueur-1.0.1" ]

  run panel_activate_release "1.0.0"
  [ "$status" -eq 0 ]
  [ "$(panel_current_version)" = "1.0.0" ]
  [ "$(cat "$PANEL_ROOT/app/public/marqueur.txt")" = "marqueur-1.0.0" ]
}

@test "activating a version that is not installed changes nothing" {
  panel_install_release "1.0.0" "$(make_archive 1.0.0)"
  panel_activate_release "1.0.0"

  run panel_activate_release "9.9.9"
  [ "$status" -eq 1 ]
  [[ "$output" == *"n'est pas installée"* ]] || return 1
  # the link still points at a version that exists
  [ "$(panel_current_version)" = "1.0.0" ]
  [ -f "$PANEL_ROOT/app/VERSION" ]
}

@test "installing a version twice is refused rather than overwritten" {
  panel_install_release "1.0.0" "$(make_archive 1.0.0)"

  run panel_install_release "1.0.0" "$(make_archive 1.0.0)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"déjà installée"* ]] || return 1
}

@test "pruning keeps the newest releases and never the served one" {
  local v
  for v in 1.0.0 1.0.1 1.1.0 1.10.0; do
    panel_install_release "$v" "$(make_archive "$v")"
  done
  # served version is an old one, as after a rollback
  panel_activate_release "1.0.0"

  run panel_prune_releases 2
  [ "$status" -eq 0 ]

  # the two newest by version order, plus the served one
  [ -d "$PANEL_ROOT/releases/1.10.0" ]
  [ -d "$PANEL_ROOT/releases/1.1.0" ]
  [ -d "$PANEL_ROOT/releases/1.0.0" ]
  [ ! -d "$PANEL_ROOT/releases/1.0.1" ]
  # and the site still serves
  [ -f "$PANEL_ROOT/app/VERSION" ]
}

@test "the app link is replaced by a rename, never left dangling" {
  panel_install_release "1.0.0" "$(make_archive 1.0.0)"
  panel_activate_release "1.0.0"

  run panel_activate_release "1.0.0"
  [ "$status" -eq 0 ]
  # no leftover temporary link beside it
  run bash -c "ls -a '$PANEL_ROOT' | grep -c '^\\.app\\.'"
  [ "$output" = "0" ]
}
