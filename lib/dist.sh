#!/usr/bin/env bash
# lib/dist.sh — resolving a panel version and fetching a verified archive.
#
# The panel is distributed as one archive per version, published in the
# public `ranel-dist` repository, and listed in a manifest that the
# installer and panel-update.sh both read. No git, no deploy key, no
# access to the private source repository from any installed server.
#
# The manifest is tab-separated, not JSON, on purpose: it is read by bash
# at a point where nothing has been installed yet — no jq, no php, no
# python guaranteed. Parsing our own line-oriented format with awk costs
# nothing and keeps the promise that the gate runs before the first
# system change.
#
#   # <version>  <released_at>  <sha256>  <url>
#   1.0.0        2026-10-01     9f2c…     https://…/ranel-1.0.0.tar.gz
#
# "latest" is not a field: it is the highest version in the file. A field
# could point at a row that does not exist; a computed maximum cannot.

DIST_MANIFEST_URL="${DIST_MANIFEST_URL:-https://raw.githubusercontent.com/RobinThijsen/ranel-dist/main/versions.tsv}"

# bats only: lets the tests serve a manifest and an archive from file://.
# Production refuses anything but https — an archive fetched over http
# could be replaced in transit, which would make the checksum pointless
# since the manifest travels the same road.
DIST_ALLOW_INSECURE_URL="${DIST_ALLOW_INSECURE_URL:-0}"

dist_valid_version() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

dist_valid_sha256() {
  [[ "$1" =~ ^[0-9a-f]{64}$ ]]
}

dist_valid_url() {
  case "$1" in
    https://*) return 0 ;;
    file://*) [ "$DIST_ALLOW_INSECURE_URL" = "1" ] && return 0 ;;
  esac

  return 1
}

# Writes the manifest to $1. Fails without touching anything else: this is
# the gate, and a manifest we cannot read is a reason to stop before the
# first system change.
dist_fetch_manifest() {
  local dest="$1"

  if ! curl -fsSL --max-time 30 "$DIST_MANIFEST_URL" -o "$dest"; then
    echo "Erreur : le manifeste des versions est injoignable (${DIST_MANIFEST_URL})." >&2
    return 1
  fi

  if [ ! -s "$dest" ]; then
    echo "Erreur : le manifeste des versions est vide (${DIST_MANIFEST_URL})." >&2
    return 1
  fi

  return 0
}

# Every data row is validated, and a single malformed one is fatal. A
# manifest we cannot fully trust is a manifest we do not use: silently
# skipping a bad row is how one ends up installing an older version than
# the one that was asked for.
#
# Prints "<version>\t<sha256>\t<url>" for $2 ("latest" or an exact
# version).
dist_resolve_version() {
  local manifest="$1"
  local wanted="$2"
  local line version released sha url
  local -a versions=()
  local found=""

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%$'\r'}"
    case "$line" in
      ''|'#'*) continue ;;
    esac

    IFS=$'\t' read -r version released sha url extra <<<"$line"

    if [ -n "${extra:-}" ] || [ -z "${url:-}" ]; then
      echo "Erreur : ligne mal formée dans le manifeste : ${line}" >&2
      return 1
    fi
    dist_valid_version "$version" || { echo "Erreur : version invalide dans le manifeste : ${version}" >&2; return 1; }
    dist_valid_sha256 "$sha" || { echo "Erreur : somme de contrôle invalide pour ${version}." >&2; return 1; }
    dist_valid_url "$url" || { echo "Erreur : URL non https pour ${version} : ${url}" >&2; return 1; }

    versions+=("$version")
    if [ "$version" = "$wanted" ]; then
      found="${version}"$'\t'"${sha}"$'\t'"${url}"
    fi
  done < "$manifest"

  if [ "${#versions[@]}" -eq 0 ]; then
    echo "Erreur : le manifeste ne contient aucune version." >&2
    return 1
  fi

  if [ "$wanted" = "latest" ]; then
    local highest
    highest="$(printf '%s\n' "${versions[@]}" | sort -V | tail -1)"
    dist_resolve_version "$manifest" "$highest"
    return $?
  fi

  if [ -z "$found" ]; then
    echo "Erreur : la version ${wanted} n'existe pas. Versions publiées : $(printf '%s ' "${versions[@]}")" >&2
    return 1
  fi

  echo "$found"
  return 0
}

# Downloads to $3 and verifies it against $2 **before** anyone unpacks it.
# A failed check removes the file: half-verified bytes on disk are an
# invitation to use them anyway.
dist_fetch_archive() {
  local url="$1"
  local expected="$2"
  local dest="$3"
  local actual

  dist_valid_url "$url" || { echo "Erreur : URL d'archive refusée : ${url}" >&2; return 1; }
  dist_valid_sha256 "$expected" || { echo "Erreur : somme de contrôle attendue invalide." >&2; return 1; }

  if ! curl -fsSL --max-time 600 "$url" -o "$dest"; then
    echo "Erreur : téléchargement de l'archive impossible (${url})." >&2
    rm -f "$dest"
    return 1
  fi

  actual="$(sha256sum "$dest" | cut -d' ' -f1)"

  if [ "$actual" != "$expected" ]; then
    rm -f "$dest"
    echo "Erreur : l'archive ne correspond pas à sa somme de contrôle (attendu ${expected}, obtenu ${actual}). Rien n'a été déplié." >&2
    return 1
  fi

  return 0
}

# Unpacks into an empty directory. --strip-components=1 because the
# archive carries a single top-level ranel-<version>/ directory, so the
# release directory is named by us and not by whoever built the tarball.
dist_unpack_archive() {
  local archive="$1"
  local dest="$2"

  mkdir -p "$dest"
  if ! tar xzf "$archive" -C "$dest" --strip-components=1; then
    echo "Erreur : l'archive n'a pas pu être dépliée dans ${dest}." >&2
    return 1
  fi

  if [ ! -f "${dest}/VERSION" ] || [ ! -f "${dest}/artisan" ]; then
    echo "Erreur : l'archive ne ressemble pas à une distribution du panel (VERSION ou artisan manquant)." >&2
    return 1
  fi

  return 0
}
