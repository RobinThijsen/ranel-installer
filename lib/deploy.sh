#!/usr/bin/env bash
# lib/deploy.sh

render_panel_env() {
  local env_example_path="$1"
  local db_name="$2"
  local db_user="$3"
  local db_password="$4"
  local app_url="$5"
  local app_key="$6"

  local rendered
  rendered="$(sed \
    -e "s|^DB_DATABASE=.*|DB_DATABASE=${db_name}|" \
    -e "s|^DB_USERNAME=.*|DB_USERNAME=${db_user}|" \
    -e "s|^DB_PASSWORD=.*|DB_PASSWORD=${db_password}|" \
    -e "s|^APP_URL=.*|APP_URL=${app_url}|" \
    -e "s|^APP_KEY=.*|APP_KEY=${app_key}|" \
    "$env_example_path")"

  echo "$rendered" | grep -q "^DB_DATABASE=" || rendered="${rendered}
DB_DATABASE=${db_name}"
  echo "$rendered" | grep -q "^DB_USERNAME=" || rendered="${rendered}
DB_USERNAME=${db_user}"
  echo "$rendered" | grep -q "^DB_PASSWORD=" || rendered="${rendered}
DB_PASSWORD=${db_password}"
  echo "$rendered" | grep -q "^APP_URL=" || rendered="${rendered}
APP_URL=${app_url}"
  echo "$rendered" | grep -q "^APP_KEY=" || rendered="${rendered}
APP_KEY=${app_key}"

  echo "$rendered"
}

deploy_panel_app() {
  local repo_url="$1"
  local key_path="$2"
  local target_dir="$3"
  local domain="$4"
  local db_name="$5"
  local db_user="$6"
  local db_password="$7"
  local admin_password="$8"

  log_info "Cloning panel app from ${repo_url} into ${target_dir}"
  GIT_SSH_COMMAND="ssh -i ${key_path} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" \
    git clone --depth 1 "$repo_url" "$target_dir"

  shred -u "$key_path" 2>/dev/null || rm -f "$key_path"
  log_info "Deploy key at ${key_path} deleted after use"

  local app_key
  app_key="base64:$(openssl rand -base64 32)"

  render_panel_env "${target_dir}/.env.example" "$db_name" "$db_user" "$db_password" \
    "https://${domain}" "$app_key" > "${target_dir}/.env"
  chmod 640 "${target_dir}/.env"

  log_info "Running composer install"
  (cd "$target_dir" && composer install --no-dev --optimize-autoloader)

  log_info "Running database migrations"
  (cd "$target_dir" && php artisan migrate --force)

  log_info "Creating initial admin account"
  (cd "$target_dir" && php artisan panel:create-admin "$PANEL_ADMIN_EMAIL" --password="$admin_password")

  chown -R panel:panel "$target_dir"
  log_info "Panel app deployed to ${target_dir}"
}
