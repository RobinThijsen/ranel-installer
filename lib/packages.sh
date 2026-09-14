#!/usr/bin/env bash
# lib/packages.sh

install_base_packages() {
  log_info "Updating apt package index"
  apt-get update -y

  log_info "Installing nginx, MySQL, Composer prerequisites, Node.js, Certbot"
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    nginx \
    mysql-server \
    php8.4-fpm php8.4-mysql php8.4-cli php8.4-xml php8.4-mbstring php8.4-curl \
    unzip curl \
    certbot python3-certbot-nginx \
    nodejs npm

  if ! command -v composer >/dev/null 2>&1; then
    log_info "Installing Composer"
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
  fi

  log_info "Base packages installed"
}
