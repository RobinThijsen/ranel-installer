#!/usr/bin/env bash
# lib/log.sh

: "${PANEL_LOG_FILE:=/var/log/panel-install.log}"

_log_write() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "${timestamp} [${level}] ${message}" >> "$PANEL_LOG_FILE"
}

log_info() {
  _log_write "INFO" "$1"
}

log_error() {
  _log_write "ERROR" "$1"
  echo "ERROR: $1" >&2
}
