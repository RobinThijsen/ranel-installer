#!/usr/bin/env bash
# lib/gate.sh
#
# The gate: everything that can say "no" runs here, before the first
# system change. An installer that is not idempotent owes that much —
# failing halfway costs a whole server.

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

# Resolves the wanted version and downloads its archive, verified against
# the checksum carried by the manifest. Prints the archive path on stdout;
# everything else goes to stderr so the caller can capture it.
#
# Nothing here touches the system: curl, sha256sum and tar are all present
# on a bare Ubuntu, which is what lets this run before apt does.
validate_distribution() {
  local wanted="$1"
  local work="$2"
  local manifest="${work}/versions.tsv"
  local resolved version sha url

  dist_fetch_manifest "$manifest" >&2 || return 1

  resolved="$(dist_resolve_version "$manifest" "$wanted")" || return 1
  version="$(printf '%s' "$resolved" | cut -f1)"
  sha="$(printf '%s' "$resolved" | cut -f2)"
  url="$(printf '%s' "$resolved" | cut -f3)"

  log_info "Version ${version} resolved from the manifest"
  echo "Version à installer : ${version}" >&2

  dist_fetch_archive "$url" "$sha" "${work}/ranel-${version}.tar.gz" >&2 || return 1
  log_info "Archive of ${version} downloaded and verified"
  echo "Archive vérifiée (sha256 ${sha})" >&2

  printf '%s\t%s\n' "$version" "${work}/ranel-${version}.tar.gz"
}
