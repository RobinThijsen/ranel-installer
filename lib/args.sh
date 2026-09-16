#!/usr/bin/env bash
# lib/args.sh

parse_install_args() {
  PANEL_DOMAIN=""
  PANEL_REPO_URL=""
  PANEL_DEPLOY_KEY_PATH=""
  PANEL_ADMIN_EMAIL=""
  PANEL_SKIP_SSL=0

  for arg in "$@"; do
    case "$arg" in
      --domain=*) PANEL_DOMAIN="${arg#--domain=}" ;;
      --repo-url=*) PANEL_REPO_URL="${arg#--repo-url=}" ;;
      --deploy-key=*) PANEL_DEPLOY_KEY_PATH="${arg#--deploy-key=}" ;;
      --admin-email=*) PANEL_ADMIN_EMAIL="${arg#--admin-email=}" ;;
      --skip-ssl) PANEL_SKIP_SSL=1 ;;
      *)
        echo "Unknown argument: $arg" >&2
        return 1
        ;;
    esac
  done

  [ -n "$PANEL_DOMAIN" ] || { echo "--domain is required" >&2; return 1; }
  [ -n "$PANEL_REPO_URL" ] || { echo "--repo-url is required" >&2; return 1; }
  [ -n "$PANEL_DEPLOY_KEY_PATH" ] || { echo "--deploy-key is required" >&2; return 1; }
  [ -n "$PANEL_ADMIN_EMAIL" ] || { echo "--admin-email is required" >&2; return 1; }

  return 0
}
