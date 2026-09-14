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
