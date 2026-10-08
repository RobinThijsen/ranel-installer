# Tests for lib/dist.sh. Run with: bats tests/bats
#
# Everything here runs against a manifest and an archive served from
# file://, which is why lib/dist.sh has DIST_ALLOW_INSECURE_URL.

setup() {
  export PANEL_LOG_FILE="$BATS_TEST_TMPDIR/install.log"
  source "$BATS_TEST_DIRNAME/../../lib/log.sh"
  source "$BATS_TEST_DIRNAME/../../lib/dist.sh"
  export DIST_ALLOW_INSECURE_URL=1

  MANIFEST="$BATS_TEST_TMPDIR/versions.tsv"

  # a real archive, so the checksum is a real checksum
  ARCHIVE_SRC="$BATS_TEST_TMPDIR/build/ranel-1.0.1"
  mkdir -p "$ARCHIVE_SRC/app"
  echo "1.0.1" > "$ARCHIVE_SRC/VERSION"
  : > "$ARCHIVE_SRC/artisan"
  ARCHIVE="$BATS_TEST_TMPDIR/ranel-1.0.1.tar.gz"
  tar czf "$ARCHIVE" -C "$BATS_TEST_TMPDIR/build" "ranel-1.0.1"
  SHA="$(sha256sum "$ARCHIVE" | cut -d' ' -f1)"

  OTHER_SHA="$(printf 'autre' | sha256sum | cut -d' ' -f1)"
}

write_manifest() {
  cat > "$MANIFEST"
}

# --- résolution de version ----------------------------------------------------

@test "latest is the highest version, whatever the order of the rows" {
  write_manifest <<EOT
# <version>	<released_at>	<sha256>	<url>
1.0.0	2026-10-01	${OTHER_SHA}	https://example.test/ranel-1.0.0.tar.gz

1.10.0	2026-10-05	${OTHER_SHA}	https://example.test/ranel-1.10.0.tar.gz
1.2.0	2026-10-03	${OTHER_SHA}	https://example.test/ranel-1.2.0.tar.gz
EOT

  run dist_resolve_version "$MANIFEST" latest
  [ "$status" -eq 0 ]
  # 1.10.0, not 1.2.0: a version is not a decimal number
  [ "$(echo "$output" | cut -f1)" = "1.10.0" ]
  [ "$(echo "$output" | cut -f3)" = "https://example.test/ranel-1.10.0.tar.gz" ]
}

@test "a pinned version is resolved exactly, and an unknown one is refused" {
  write_manifest <<EOT
1.0.0	2026-10-01	${OTHER_SHA}	https://example.test/ranel-1.0.0.tar.gz
1.1.0	2026-10-05	${SHA}	https://example.test/ranel-1.1.0.tar.gz
EOT

  run dist_resolve_version "$MANIFEST" "1.0.0"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | cut -f1)" = "1.0.0" ]

  run dist_resolve_version "$MANIFEST" "9.9.9"
  [ "$status" -eq 1 ]
  [[ "$output" == *"n'existe pas"* ]] || return 1
  # and it says what does exist, so the message is actionable
  [[ "$output" == *"1.0.0"* ]] || return 1
}

@test "a single malformed row is fatal, never silently skipped" {
  # skipping it would mean installing an older version than the one asked
  # for, without saying so
  write_manifest <<EOT
1.0.0	2026-10-01	${OTHER_SHA}	https://example.test/ranel-1.0.0.tar.gz
1.1.0	2026-10-05	pas-une-somme	https://example.test/ranel-1.1.0.tar.gz
EOT

  run dist_resolve_version "$MANIFEST" latest
  [ "$status" -eq 1 ]
  [[ "$output" == *"somme de contrôle invalide"* ]] || return 1
}

@test "a non-https url is refused, a version that is not semver too" {
  write_manifest <<EOT
1.0.0	2026-10-01	${OTHER_SHA}	http://example.test/ranel-1.0.0.tar.gz
EOT
  DIST_ALLOW_INSECURE_URL=0 run dist_resolve_version "$MANIFEST" latest
  [ "$status" -eq 1 ]
  [[ "$output" == *"non https"* ]] || return 1

  write_manifest <<EOT
main	2026-10-01	${OTHER_SHA}	https://example.test/ranel.tar.gz
EOT
  run dist_resolve_version "$MANIFEST" latest
  [ "$status" -eq 1 ]
  [[ "$output" == *"version invalide"* ]] || return 1
}

@test "an empty or comment-only manifest is refused" {
  write_manifest <<EOT
# rien que des commentaires
EOT

  run dist_resolve_version "$MANIFEST" latest
  [ "$status" -eq 1 ]
  [[ "$output" == *"aucune version"* ]] || return 1
}

# --- téléchargement et vérification -------------------------------------------

@test "an archive matching its checksum is kept, and unpacks" {
  run dist_fetch_archive "file://${ARCHIVE}" "$SHA" "$BATS_TEST_TMPDIR/dl.tar.gz"
  [ "$status" -eq 0 ]
  [ -s "$BATS_TEST_TMPDIR/dl.tar.gz" ]

  run dist_unpack_archive "$BATS_TEST_TMPDIR/dl.tar.gz" "$BATS_TEST_TMPDIR/release"
  [ "$status" -eq 0 ]
  # --strip-components=1: the release directory is named by us
  [ -f "$BATS_TEST_TMPDIR/release/VERSION" ]
  [ -f "$BATS_TEST_TMPDIR/release/artisan" ]
  [ "$(cat "$BATS_TEST_TMPDIR/release/VERSION")" = "1.0.1" ]
}

@test "an archive that does not match its checksum is deleted, not unpacked" {
  run dist_fetch_archive "file://${ARCHIVE}" "$OTHER_SHA" "$BATS_TEST_TMPDIR/dl.tar.gz"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ne correspond pas à sa somme de contrôle"* ]] || return 1
  [[ "$output" == *"Rien n'a été déplié"* ]] || return 1
  # half-verified bytes on disk are an invitation to use them anyway
  [ ! -e "$BATS_TEST_TMPDIR/dl.tar.gz" ]
}

@test "a download that fails leaves nothing behind" {
  run dist_fetch_archive "file://${BATS_TEST_TMPDIR}/inexistant.tar.gz" "$SHA" "$BATS_TEST_TMPDIR/dl.tar.gz"
  [ "$status" -eq 1 ]
  [ ! -e "$BATS_TEST_TMPDIR/dl.tar.gz" ]
}

@test "something that is not a panel distribution is refused after unpacking" {
  mkdir -p "$BATS_TEST_TMPDIR/junk/autre-chose"
  echo hello > "$BATS_TEST_TMPDIR/junk/autre-chose/README"
  tar czf "$BATS_TEST_TMPDIR/junk.tar.gz" -C "$BATS_TEST_TMPDIR/junk" "autre-chose"

  run dist_unpack_archive "$BATS_TEST_TMPDIR/junk.tar.gz" "$BATS_TEST_TMPDIR/junk-release"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ne ressemble pas à une distribution du panel"* ]] || return 1
}

# --- le manifeste lui-même ----------------------------------------------------

@test "an unreachable manifest stops everything with a readable message" {
  DIST_MANIFEST_URL="file://${BATS_TEST_TMPDIR}/pas-de-manifeste.tsv"
  run dist_fetch_manifest "$BATS_TEST_TMPDIR/fetched.tsv"
  [ "$status" -eq 1 ]
  [[ "$output" == *"injoignable"* ]] || return 1
}

@test "an empty manifest is refused rather than treated as no versions" {
  : > "$BATS_TEST_TMPDIR/vide.tsv"
  DIST_MANIFEST_URL="file://${BATS_TEST_TMPDIR}/vide.tsv"
  run dist_fetch_manifest "$BATS_TEST_TMPDIR/fetched.tsv"
  [ "$status" -eq 1 ]
  [[ "$output" == *"vide"* ]] || return 1
}
