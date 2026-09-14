#!/usr/bin/env bash
# lib/nginx.sh

render_panel_vhost() {
  local domain="$1"
  local app_root="$2"

  cat <<EOF
server {
    listen 80;
    server_name ${domain};
    root ${app_root}/public;

    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.4-fpm.sock;
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
  render_panel_vhost "$domain" "$app_root" > "$vhost_path"
  ln -sf "$vhost_path" "${sites_enabled_dir}/panel.conf"

  nginx -t
  systemctl reload nginx
  log_info "Nginx vhost written for ${domain} and reloaded"
}
