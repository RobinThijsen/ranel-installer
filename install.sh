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
# shellcheck source=lib/php.sh
source "${SCRIPT_DIR}/lib/php.sh"
# shellcheck source=lib/scripts_dir.sh
source "${SCRIPT_DIR}/lib/scripts_dir.sh"
# shellcheck source=lib/deploy.sh
source "${SCRIPT_DIR}/lib/deploy.sh"
# shellcheck source=lib/nginx.sh
source "${SCRIPT_DIR}/lib/nginx.sh"
# shellcheck source=lib/ssl.sh
source "${SCRIPT_DIR}/lib/ssl.sh"
# shellcheck source=lib/queue.sh
source "${SCRIPT_DIR}/lib/queue.sh"
# shellcheck source=lib/scheduler.sh
source "${SCRIPT_DIR}/lib/scheduler.sh"
# shellcheck source=lib/logrotate.sh
source "${SCRIPT_DIR}/lib/logrotate.sh"

PANEL_APP_DIR="/opt/panel/app"
PANEL_SCRIPTS_DIR="/opt/panel/scripts"
PANEL_SUDOERS_FILE="/etc/sudoers.d/panel"
PANEL_DB_NAME="panel"
PANEL_DB_USER="panel"

trap 'log_error "Installation échouée. Ce script n'\''est pas idempotent : repars d'\''un serveur neuf. Log complet : ${PANEL_LOG_FILE}"; echo "Installation échouée. Ce script n'\''est pas idempotent : repars d'\''un serveur neuf. Log complet : ${PANEL_LOG_FILE}" >&2' ERR

# Capture the full output of every subsequent command (apt, composer, artisan,
# certbot, nginx) into the install log, in addition to the terminal.
exec > >(tee -a "$PANEL_LOG_FILE") 2>&1

main() {
  parse_install_args "$@"

  ensure_git_installed

  log_info "Validating deploy key before touching the system"
  if ! validate_git_key "$PANEL_REPO_URL" "$PANEL_DEPLOY_KEY_PATH"; then
    echo "Deploy key rejected. Aborting — nothing was installed." >&2
    exit 1
  fi

  install_base_packages
  install_composer
  create_panel_user
  setup_panel_php_pool
  setup_scripts_dir "$PANEL_SCRIPTS_DIR"
  setup_sudoers_file "$PANEL_SUDOERS_FILE"

  local db_password
  db_password="$(openssl rand -base64 24)"
  mysql <<SQL
CREATE DATABASE IF NOT EXISTS ${PANEL_DB_NAME};
CREATE USER IF NOT EXISTS '${PANEL_DB_USER}'@'localhost' IDENTIFIED BY '${db_password}';
GRANT ALL PRIVILEGES ON ${PANEL_DB_NAME}.* TO '${PANEL_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

  local admin_password
  admin_password="$(openssl rand -base64 18)"

  local scheme="https"
  if [ "$PANEL_SKIP_SSL" -eq 1 ]; then
    scheme="http"
  fi

  deploy_panel_app "$PANEL_REPO_URL" "$PANEL_DEPLOY_KEY_PATH" "$PANEL_APP_DIR" \
    "$PANEL_DOMAIN" "$PANEL_DB_NAME" "$PANEL_DB_USER" "$db_password" "$admin_password" "$scheme"

  apply_package_manifest "${PANEL_APP_DIR}/system/packages.txt"
  sync_privileged_scripts "${PANEL_APP_DIR}/privileged-scripts" "$PANEL_SCRIPTS_DIR" "$PANEL_SUDOERS_FILE"

  setup_queue_worker "$PANEL_APP_DIR"
  setup_scheduler "$PANEL_APP_DIR"
  setup_panel_logrotate "$PANEL_FPM_VERSION"

  write_panel_vhost "$PANEL_DOMAIN" "$PANEL_APP_DIR"
  if [ "$PANEL_SKIP_SSL" -eq 1 ]; then
    log_info "--skip-ssl given: no Let's Encrypt certificate requested, panel served over plain HTTP (local/test use only)"
  else
    issue_panel_certificate "$PANEL_DOMAIN"
  fi

  echo ""
  echo "Panel installed successfully."
  echo "URL: ${scheme}://${PANEL_DOMAIN}"
  echo "Admin account: ${PANEL_ADMIN_EMAIL}"
  echo "Admin password: ${admin_password}"
}

main "$@"
