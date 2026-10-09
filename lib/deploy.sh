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

PANEL_HOME="${PANEL_HOME:-/var/lib/panel}"

# The panel user's passwd home is /opt/panel, which is root-owned on
# purpose — so artisan gets a home of its own for its caches. Same
# directory panel-update.sh uses, for the same reason.
ensure_panel_home() {
  mkdir -p "${PANEL_HOME}/.ssh"
  chown "${PANEL_OWNER}:${PANEL_GROUP}" "$PANEL_HOME" "${PANEL_HOME}/.ssh"
  chmod 700 "$PANEL_HOME" "${PANEL_HOME}/.ssh"
}

# artisan runs as the panel user, never as root: the release and shared/
# already belong to panel, and a root-owned log file inside a
# panel-owned directory is a bug that only shows up weeks later.
as_panel_app() {
  runuser -u "$PANEL_OWNER" -- env HOME="$PANEL_HOME" \
    bash -c 'cd "$1" && shift && exec "$@"' bash "${PANEL_ROOT}/app" "$@"
}

# Installs <version> from <archive> and makes it the served release.
# No composer, no npm: the archive already carries vendor/ and the
# compiled assets, so nothing is built on the customer's machine — and no
# Composer credential is ever needed there.
install_panel_app() {
  local version="$1"
  local archive="$2"
  local domain="$3"
  local db_name="$4"
  local db_user="$5"
  local db_password="$6"
  local admin_password="$7"
  local scheme="${8:-https}"
  local shared release app_key

  log_info "Installing panel ${version} from ${archive}"
  panel_install_release "$version" "$archive" || return 1

  shared="$(panel_shared_dir)"
  release="$(panel_releases_dir)/${version}"

  if [ ! -f "${shared}/.env" ]; then
    app_key="base64:$(openssl rand -base64 32)"
    render_panel_env "${release}/.env.example" "$db_name" "$db_user" "$db_password" \
      "${scheme}://${domain}" "$app_key" > "${shared}/.env"
    chmod 640 "${shared}/.env"
    chown "${PANEL_OWNER}:${PANEL_GROUP}" "${shared}/.env"
    log_info "Panel .env rendered in ${shared}"
  fi

  ensure_panel_home
  panel_activate_release "$version" || return 1
  log_info "Panel ${version} is the served release"

  log_info "Running database migrations"
  as_panel_app php artisan migrate --force

  log_info "Creating initial admin account"
  as_panel_app php artisan panel:create-admin "$PANEL_ADMIN_EMAIL" --password="$admin_password"

  log_info "Panel ${version} installed in ${PANEL_ROOT}"
}
