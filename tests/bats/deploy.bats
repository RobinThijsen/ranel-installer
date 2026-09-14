setup() {
  source "$BATS_TEST_DIRNAME/../../lib/deploy.sh"
  export FIXTURE_ENV_EXAMPLE="$BATS_TEST_DIRNAME/../fixtures/fake-panel-app/.env.example"
}

@test "render_panel_env fills DB and app values from .env.example" {
  run render_panel_env "$FIXTURE_ENV_EXAMPLE" "panel_db" "panel_user" "s3cret" "https://panel.example.com" "base64:fakekey"

  [ "$status" -eq 0 ]
  [[ "$output" == *"DB_DATABASE=panel_db"* ]]
  [[ "$output" == *"DB_USERNAME=panel_user"* ]]
  [[ "$output" == *"DB_PASSWORD=s3cret"* ]]
  [[ "$output" == *"APP_URL=https://panel.example.com"* ]]
  [[ "$output" == *"APP_KEY=base64:fakekey"* ]]
}

@test "render_panel_env appends APP_KEY when missing from .env.example" {
  local env_example="$BATS_TEST_TMPDIR/.env.example"
  cat > "$env_example" <<'EOF'
APP_NAME=Panel
APP_ENV=production
APP_URL=http://localhost
DB_CONNECTION=mysql
DB_DATABASE=panel
DB_USERNAME=panel
DB_PASSWORD=
EOF

  run render_panel_env "$env_example" "panel_db" "panel_user" "s3cret" "https://panel.example.com" "base64:fakekey"

  [ "$status" -eq 0 ]
  [[ "$output" == *"APP_KEY=base64:fakekey"* ]]
}
