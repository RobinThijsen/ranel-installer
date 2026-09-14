#!/usr/bin/env bash
# lib/gate.sh

validate_git_key() {
  local repo_url="$1"
  local key_path="$2"

  if GIT_SSH_COMMAND="ssh -i ${key_path} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" \
     git ls-remote "$repo_url" >/dev/null 2>&1; then
    log_info "Deploy key validated against ${repo_url}"
    return 0
  else
    log_error "Deploy key rejected by ${repo_url} — aborting before any system change"
    return 1
  fi
}
