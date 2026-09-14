#!/usr/bin/env bash
# lib/packages.sh

ensure_git_installed() {
  if command -v git >/dev/null 2>&1; then
    return 0
  fi

  log_info "git not found — installing it before the deploy-key gate can run"
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y git
  log_info "git installed"
}

add_php_repository() {
  local distro_id=""
  # shellcheck disable=SC1091
  . /etc/os-release
  distro_id="$ID"

  case "$distro_id" in
    ubuntu)
      log_info "Ubuntu detected — adding ppa:ondrej/php for PHP 8.4 packages"
      apt-get install -y software-properties-common
      add-apt-repository -y ppa:ondrej/php
      apt-get update -y
      ;;
    debian)
      log_info "Debian detected — adding packages.sury.org for PHP 8.4 packages"
      apt-get install -y apt-transport-https lsb-release ca-certificates curl
      curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg
      echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" \
        > /etc/apt/sources.list.d/php.list
      apt-get update -y
      ;;
    *)
      log_error "Unsupported distro '${distro_id}' for PHP 8.4 third-party repository — expected ubuntu or debian"
      return 1
      ;;
  esac
}

install_base_packages() {
  log_info "Updating apt package index"
  apt-get update -y

  add_php_repository

  log_info "Installing nginx, MySQL, PHP 8.4, Composer, Node.js, Certbot"
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    nginx \
    mysql-server \
    php8.4-fpm php8.4-mysql php8.4-cli php8.4-xml php8.4-mbstring php8.4-curl \
    unzip curl \
    certbot python3-certbot-nginx \
    nodejs npm \
    composer

  log_info "Base packages installed"
}
