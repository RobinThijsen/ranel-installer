#!/usr/bin/env bash
# lib/nginx.sh

# Extensions of the panel's own vhost (phpMyAdmin today) drop a file in
# PANEL_NGINX_D rather than rewriting this vhost — certbot edits it once
# the certificate is issued, and those edits have to survive.
PANEL_NGINX_D="${PANEL_NGINX_D:-/etc/nginx/ranel/panel.d}"

render_panel_vhost() {
  local domain="$1"
  local app_root="$2"

  cat <<EOF
server {
    listen 80;
    server_name ${domain};
    root ${app_root}/public;
    include ${PANEL_NGINX_D}/*.conf;

    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.4-fpm-panel.sock;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF
}

write_panel_vhost() {
  local domain="$1"
  local app_root="$2"
  local sites_available_dir="${3:-/etc/nginx/sites-available}"
  local sites_enabled_dir="${4:-/etc/nginx/sites-enabled}"

  local vhost_path="${sites_available_dir}/panel.conf"
  mkdir -p "$PANEL_NGINX_D"
  render_panel_vhost "$domain" "$app_root" > "$vhost_path"
  ln -sf "$vhost_path" "${sites_enabled_dir}/panel.conf"

  nginx -t
  systemctl reload nginx
  log_info "Nginx vhost written for ${domain} and reloaded"
}
