setup() {
  source "$BATS_TEST_DIRNAME/../../lib/args.sh"
}

@test "parse_install_args fills the expected globals" {
  parse_install_args \
    --domain=panel.example.com \
    --repo-url=git@github.com:agency/panel-app.git \
    --deploy-key=/tmp/fake-key \
    --admin-email=admin@example.com

  [ "$PANEL_DOMAIN" = "panel.example.com" ]
  [ "$PANEL_REPO_URL" = "git@github.com:agency/panel-app.git" ]
  [ "$PANEL_DEPLOY_KEY_PATH" = "/tmp/fake-key" ]
  [ "$PANEL_ADMIN_EMAIL" = "admin@example.com" ]
}

@test "parse_install_args fails when --domain is missing" {
  run parse_install_args \
    --repo-url=git@github.com:agency/panel-app.git \
    --deploy-key=/tmp/fake-key \
    --admin-email=admin@example.com
  [ "$status" -ne 0 ]
  [[ "$output" == *"--domain is required"* ]]
}

@test "parse_install_args fails when --repo-url is missing" {
  run parse_install_args \
    --domain=panel.example.com \
    --deploy-key=/tmp/fake-key \
    --admin-email=admin@example.com
  [ "$status" -ne 0 ]
  [[ "$output" == *"--repo-url is required"* ]]
}

@test "parse_install_args fails when --deploy-key is missing" {
  run parse_install_args \
    --domain=panel.example.com \
    --repo-url=git@github.com:agency/panel-app.git \
    --admin-email=admin@example.com
  [ "$status" -ne 0 ]
  [[ "$output" == *"--deploy-key is required"* ]]
}

@test "parse_install_args fails when --admin-email is missing" {
  run parse_install_args \
    --domain=panel.example.com \
    --repo-url=git@github.com:agency/panel-app.git \
    --deploy-key=/tmp/fake-key
  [ "$status" -ne 0 ]
  [[ "$output" == *"--admin-email is required"* ]]
}

@test "parse_install_args fails on an unknown argument" {
  run parse_install_args \
    --domain=panel.example.com \
    --repo-url=git@github.com:agency/panel-app.git \
    --deploy-key=/tmp/fake-key \
    --admin-email=admin@example.com \
    --bogus=foo
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown argument: --bogus=foo"* ]]
}
