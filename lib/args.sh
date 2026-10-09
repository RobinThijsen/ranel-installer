#!/usr/bin/env bash
# lib/args.sh

parse_install_args() {
  PANEL_DOMAIN=""
  PANEL_ADMIN_EMAIL=""
  PANEL_VERSION="latest"
  PANEL_SKIP_SSL=0

  for arg in "$@"; do
    case "$arg" in
      --domain=*) PANEL_DOMAIN="${arg#--domain=}" ;;
      --admin-email=*) PANEL_ADMIN_EMAIL="${arg#--admin-email=}" ;;
      --version=*) PANEL_VERSION="${arg#--version=}" ;;
      --skip-ssl) PANEL_SKIP_SSL=1 ;;
      *)
        echo "Unknown argument: $arg" >&2
        return 1
        ;;
    esac
  done

  [ -n "$PANEL_DOMAIN" ] || { echo "--domain is required" >&2; return 1; }
  [ -n "$PANEL_ADMIN_EMAIL" ] || { echo "--admin-email is required" >&2; return 1; }

  if [ "$PANEL_VERSION" != "latest" ] && ! [[ "$PANEL_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "--version must be latest or <major>.<minor>.<patch>" >&2
    return 1
  fi

  return 0
}
