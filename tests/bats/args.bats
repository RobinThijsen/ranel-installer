setup() {
  source "$BATS_TEST_DIRNAME/../../lib/args.sh"
}

@test "parse_install_args fills the expected globals" {
  parse_install_args \
    --domain=panel.example.com \
    --admin-email=admin@example.com

  [ "$PANEL_DOMAIN" = "panel.example.com" ]
  [ "$PANEL_ADMIN_EMAIL" = "admin@example.com" ]
  # no repository and no key any more: the panel is installed from an
  # archive, so no server ever reads the source repository
  [ "$PANEL_VERSION" = "latest" ]
}

@test "parse_install_args fails when --domain is missing" {
  run parse_install_args --admin-email=admin@example.com
  [ "$status" -ne 0 ]
  [[ "$output" == *"--domain is required"* ]] || return 1
}

@test "parse_install_args fails when --admin-email is missing" {
  run parse_install_args --domain=panel.example.com
  [ "$status" -ne 0 ]
  [[ "$output" == *"--admin-email is required"* ]] || return 1
}

@test "parse_install_args fails on an unknown argument" {
  run parse_install_args \
    --domain=panel.example.com \
    --admin-email=admin@example.com \
    --bogus=foo
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown argument: --bogus=foo"* ]] || return 1
}

@test "the old repository and key arguments are no longer accepted" {
  # an operator reusing yesterday's command line must be told, not
  # silently installed with something they did not choose
  run parse_install_args \
    --domain=panel.example.com \
    --admin-email=admin@example.com \
    --repo-url=git@github.com:agency/panel-app.git
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown argument: --repo-url"* ]] || return 1

  run parse_install_args \
    --domain=panel.example.com \
    --admin-email=admin@example.com \
    --deploy-key=/tmp/fake-key
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown argument: --deploy-key"* ]] || return 1
}

@test "a version is either latest or semantic" {
  parse_install_args \
    --domain=panel.example.com \
    --admin-email=admin@example.com \
    --version=1.2.3
  [ "$PANEL_VERSION" = "1.2.3" ]

  run parse_install_args \
    --domain=panel.example.com \
    --admin-email=admin@example.com \
    --version=main
  [ "$status" -ne 0 ]
  [[ "$output" == *"--version must be latest or"* ]] || return 1

  # a branch-looking value is the mistake to expect from anyone used to
  # the previous installer; so is a leading v
  run parse_install_args \
    --domain=panel.example.com \
    --admin-email=admin@example.com \
    --version=v1.2.3
  [ "$status" -ne 0 ]
}

@test "parse_install_args defaults to SSL on and accepts --skip-ssl" {
  parse_install_args \
    --domain=panel.example.com \
    --admin-email=admin@example.com
  [ "$PANEL_SKIP_SSL" -eq 0 ]

  parse_install_args \
    --domain=panel.localhost \
    --admin-email=admin@example.com \
    --skip-ssl
  [ "$PANEL_SKIP_SSL" -eq 1 ]
}
