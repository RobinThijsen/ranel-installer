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

# The distro's nodejs (18 on Ubuntu 24.04 / Debian 12) is too old for the
# panel's Vite build (Vite 7+ needs Node 20.19+): use NodeSource's Node 22
# LTS repository, same signed-keyring approach as the PHP repository.
add_node_repository() {
  local node_major="22"

  log_info "Adding NodeSource repository for Node.js ${node_major}.x"
  apt-get install -y ca-certificates curl gnupg
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${node_major}.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list
  apt-get update -y
}

install_base_packages() {
  log_info "Updating apt package index"
  apt-get update -y

  add_php_repository
  add_node_repository

  log_info "Installing nginx, MySQL, PHP 8.4, Composer, Node.js 22, Certbot"
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    nginx \
    mysql-server \
    php8.4-fpm php8.4-mysql php8.4-cli php8.4-xml php8.4-mbstring php8.4-curl php8.4-zip \
    unzip curl \
    certbot python3-certbot-nginx \
    nodejs \
    composer

  log_info "Base packages installed"
}
