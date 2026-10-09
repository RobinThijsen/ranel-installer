#!/usr/bin/env bash
# lib/release.sh — laying the panel out as releases, and swapping between them.
#
# Same layout as a site the panel deploys with releases, for the same
# reasons — and because the asymmetry was indefensible: a bad panel
# update had no way back, while the sites it hosts have had one for
# weeks.
#
#   /opt/panel/releases/<version>/   the unpacked archive
#   /opt/panel/shared/.env           the configuration, outliving releases
#   /opt/panel/shared/storage/       logs, sessions, caches — same
#   /opt/panel/app -> releases/<v>   the stable path everything references
#
# `app` stays the path named by nginx, the PHP-FPM pool, sudoers, the
# systemd units and the cron file: swapping a version changes one symlink
# and nothing else.

PANEL_ROOT="${PANEL_ROOT:-/opt/panel}"
PANEL_OWNER="${PANEL_OWNER:-panel}"
# Both are `panel` in production; the bats tests override the group,
# because a macOS user's group is not named after the user.
PANEL_GROUP="${PANEL_GROUP:-$PANEL_OWNER}"

# GNU mv renames onto an existing symlink with -T, BSD with -h. Either way
# it is a rename, so the link never briefly points nowhere.
panel_replace_symlink() {
  local from="$1"
  local to="$2"

  if mv --version >/dev/null 2>&1; then
    mv -Tf "$from" "$to"
  else
    mv -hf "$from" "$to"
  fi
}

panel_releases_dir() {
  echo "${PANEL_ROOT}/releases"
}

panel_shared_dir() {
  echo "${PANEL_ROOT}/shared"
}

# The version currently served, read from the link rather than from a file
# someone could have edited: the truth is where nginx looks.
panel_current_version() {
  local target

  [ -L "${PANEL_ROOT}/app" ] || return 1
  target="$(readlink "${PANEL_ROOT}/app")"
  basename "$target"
}

panel_release_exists() {
  [ -d "${PANEL_ROOT}/releases/$1" ]
}

# Unpacks $2 into releases/$1 and wires the shared files into it. Does not
# activate it: a release that is ready and a release that is served are
# two different things, and the migrations run in between.
panel_install_release() {
  local version="$1"
  local archive="$2"
  local releases shared release

  releases="$(panel_releases_dir)"
  shared="$(panel_shared_dir)"
  release="${releases}/${version}"

  mkdir -p "$releases" "$shared"

  if [ -e "$release" ]; then
    echo "Erreur : la version ${version} est déjà installée (${release})." >&2
    return 1
  fi

  dist_unpack_archive "$archive" "$release" || return 1

  # First install: the archive's storage becomes the shared one, so the
  # framework's directory structure exists without being invented here.
  if [ ! -d "${shared}/storage" ]; then
    if [ -d "${release}/storage" ]; then
      mv "${release}/storage" "${shared}/storage"
    else
      mkdir -p "${shared}/storage/framework/"{cache,sessions,views} "${shared}/storage/logs"
    fi
  fi

  rm -rf "${release}/storage"
  ln -sfn ../../shared/storage "${release}/storage"

  # .env is linked whether or not it exists yet: the caller renders it
  # into shared/ right after, and a dangling link for a second is better
  # than two code paths.
  rm -f "${release}/.env"
  ln -sfn ../../shared/.env "${release}/.env"

  mkdir -p "${release}/bootstrap/cache"

  chown -R "${PANEL_OWNER}:${PANEL_GROUP}" "$release" "$shared"
  chmod 750 "$shared"

  return 0
}

# Swaps the `app` link onto $1. The temporary link lives beside the target
# so the rename stays inside one filesystem.
panel_activate_release() {
  local version="$1"
  local temp="${PANEL_ROOT}/.app.$$"

  panel_release_exists "$version" || {
    echo "Erreur : la version ${version} n'est pas installée." >&2
    return 1
  }

  ln -sfn "releases/${version}" "$temp"
  chown -h "${PANEL_OWNER}:${PANEL_GROUP}" "$temp"
  panel_replace_symlink "$temp" "${PANEL_ROOT}/app"

  return 0
}

# Keeps the $1 most recent releases plus the one being served. Sorted by
# version, not by date: a rollback makes an old release the current one,
# and its directory's mtime says nothing useful afterwards.
panel_prune_releases() {
  local keep="${1:-3}"
  local releases current version

  releases="$(panel_releases_dir)"
  [ -d "$releases" ] || return 0
  current="$(panel_current_version || true)"

  local total excess
  # shellcheck disable=SC2012
  total="$(ls -1 "$releases" 2>/dev/null | wc -l | tr -d ' ')"
  excess=$(( total - keep ))
  [ "$excess" -gt 0 ] || return 0

  # `head -n -N` would be shorter but it is a GNU extension; BSD head
  # refuses a negative count, and the bats suite runs on macOS.
  # shellcheck disable=SC2012
  ls -1 "$releases" 2>/dev/null | sort -V | head -n "$excess" | while IFS= read -r version; do
    [ -n "$version" ] || continue
    [ "$version" = "$current" ] && continue
    rm -rf "${releases:?}/${version:?}"
    echo "release ${version} supprimée"
  done

  return 0
}
