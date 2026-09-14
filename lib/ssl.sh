#!/usr/bin/env bash
# lib/ssl.sh

issue_panel_certificate() {
  local domain="$1"

  log_info "Requesting Let's Encrypt certificate for ${domain}"
  if ! certbot --nginx -d "$domain" --non-interactive --agree-tos -m "$PANEL_ADMIN_EMAIL" --redirect; then
    log_error "Certbot failed for ${domain} — check that DNS already points to this server"
    return 1
  fi
  log_info "Certificate issued for ${domain}"
}
