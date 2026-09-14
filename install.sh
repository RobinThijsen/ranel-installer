#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"
# shellcheck source=lib/args.sh
source "${SCRIPT_DIR}/lib/args.sh"
# shellcheck source=lib/gate.sh
source "${SCRIPT_DIR}/lib/gate.sh"
# shellcheck source=lib/packages.sh
source "${SCRIPT_DIR}/lib/packages.sh"
# shellcheck source=lib/user.sh
source "${SCRIPT_DIR}/lib/user.sh"
# shellcheck source=lib/scripts_dir.sh
source "${SCRIPT_DIR}/lib/scripts_dir.sh"
# shellcheck source=lib/deploy.sh
source "${SCRIPT_DIR}/lib/deploy.sh"
# shellcheck source=lib/nginx.sh
source "${SCRIPT_DIR}/lib/nginx.sh"
# shellcheck source=lib/ssl.sh
source "${SCRIPT_DIR}/lib/ssl.sh"

PANEL_APP_DIR="/opt/panel/app"
PANEL_SCRIPTS_DIR="/opt/panel/scripts"
PANEL_SUDOERS_FILE="/etc/sudoers.d/panel"
PANEL_DB_NAME="panel"
PANEL_DB_USER="panel"

main() {
  parse_install_args "$@"

  log_info "Validating deploy key before touching the system"
  if ! validate_git_key "$PANEL_REPO_URL" "$PANEL_DEPLOY_KEY_PATH"; then
    echo "Deploy key rejected. Aborting — nothing was installed." >&2
    exit 1
  fi

  install_base_packages
  create_panel_user
  setup_scripts_dir "$PANEL_SCRIPTS_DIR"
  setup_sudoers_file "$PANEL_SUDOERS_FILE"

  local db_password
  db_password="$(openssl rand -base64 24)"
  mysql -e "CREATE DATABASE IF NOT EXISTS ${PANEL_DB_NAME};"
  mysql -e "CREATE USER IF NOT EXISTS '${PANEL_DB_USER}'@'localhost' IDENTIFIED BY '${db_password}';"
  mysql -e "GRANT ALL PRIVILEGES ON ${PANEL_DB_NAME}.* TO '${PANEL_DB_USER}'@'localhost';"
  mysql -e "FLUSH PRIVILEGES;"

  deploy_panel_app "$PANEL_REPO_URL" "$PANEL_DEPLOY_KEY_PATH" "$PANEL_APP_DIR" \
    "$PANEL_DOMAIN" "$PANEL_DB_NAME" "$PANEL_DB_USER" "$db_password"

  write_panel_vhost "$PANEL_DOMAIN" "$PANEL_APP_DIR"
  issue_panel_certificate "$PANEL_DOMAIN"

  echo ""
  echo "Panel installed successfully."
  echo "URL: https://${PANEL_DOMAIN}"
  echo "Admin account: ${PANEL_ADMIN_EMAIL} (password set via panel:create-admin)"
}

main "$@"
