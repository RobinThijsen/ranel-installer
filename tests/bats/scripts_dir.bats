setup() {
  export PANEL_LOG_FILE="$BATS_TEST_TMPDIR/install.log"
  source "$BATS_TEST_DIRNAME/../../lib/log.sh"
  source "$BATS_TEST_DIRNAME/../../lib/scripts_dir.sh"
}

# Portable file-mode read: GNU stat (-c) on Linux, BSD/macOS stat (-f) otherwise.
_file_mode() {
  stat -c "%a" "$1" 2>/dev/null || stat -f "%OLp" "$1"
}

@test "render_sudoers_line produces an exact-path NOPASSWD entry" {
  run render_sudoers_line "/opt/panel/scripts/create-site.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "panel ALL=(root) NOPASSWD: /opt/panel/scripts/create-site.sh" ]
}

@test "add_sudoers_entry appends the line and validates syntax" {
  local sudoers_file="$BATS_TEST_TMPDIR/sudoers.d-panel"
  : > "$sudoers_file"
  run add_sudoers_entry "/opt/panel/scripts/create-site.sh" "$sudoers_file"
  [ "$status" -eq 0 ]
  run cat "$sudoers_file"
  [[ "$output" == *"/opt/panel/scripts/create-site.sh"* ]]
}

@test "add_sudoers_entry leaves the original file unchanged when visudo rejects it" {
  local sudoers_file="$BATS_TEST_TMPDIR/sudoers.d-panel"
  echo "panel ALL=(root) NOPASSWD: /opt/panel/scripts/existing.sh" > "$sudoers_file"
  local original_content
  original_content="$(cat "$sudoers_file")"

  export PATH="$BATS_TEST_DIRNAME/../fixtures/fake-visudo-bin:$PATH"
  run add_sudoers_entry "/opt/panel/scripts/create-site.sh" "$sudoers_file"

  [ "$status" -ne 0 ]
  run cat "$sudoers_file"
  [ "$output" = "$original_content" ]
  [[ "$output" != *"create-site.sh"* ]]
  [ ! -f "${sudoers_file}.tmp" ]
}

@test "list_privileged_scripts lists .sh files sorted, ignoring non-.sh files" {
  local dir="$BATS_TEST_TMPDIR/privileged-scripts"
  mkdir -p "$dir"
  touch "$dir/zzz.sh" "$dir/aaa.sh" "$dir/mmm.sh"
  touch "$dir/README.md"

  run list_privileged_scripts "$dir"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'aaa.sh\nmmm.sh\nzzz.sh')" ]
}

@test "list_privileged_scripts ignores symlinks even when named *.sh" {
  local dir="$BATS_TEST_TMPDIR/privileged-scripts-symlink"
  mkdir -p "$dir"
  touch "$dir/real.sh"
  local target="$BATS_TEST_TMPDIR/outside-target.sh"
  printf '#!/usr/bin/env bash\necho outside\n' > "$target"
  ln -s "$target" "$dir/symlink.sh"

  run list_privileged_scripts "$dir"
  [ "$status" -eq 0 ]
  [ "$output" = "real.sh" ]
}

@test "list_privileged_scripts ignores subdirectories even when named *.sh" {
  local dir="$BATS_TEST_TMPDIR/privileged-scripts-subdir"
  mkdir -p "$dir"
  touch "$dir/real.sh"
  mkdir -p "$dir/subdir.sh"

  run list_privileged_scripts "$dir"
  [ "$status" -eq 0 ]
  [ "$output" = "real.sh" ]
}

@test "list_privileged_scripts ignores filenames with invalid characters (e.g. spaces)" {
  local dir="$BATS_TEST_TMPDIR/privileged-scripts-badname"
  mkdir -p "$dir"
  touch "$dir/real.sh"
  touch "$dir/bad name.sh"

  run list_privileged_scripts "$dir"
  [ "$status" -eq 0 ]
  [ "$output" = "real.sh" ]
}

@test "list_privileged_scripts returns nothing for an empty directory" {
  local dir="$BATS_TEST_TMPDIR/empty-privileged-scripts"
  mkdir -p "$dir"

  run list_privileged_scripts "$dir"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "list_privileged_scripts returns nothing when the directory does not exist" {
  run list_privileged_scripts "$BATS_TEST_TMPDIR/does-not-exist"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "sync_privileged_scripts copies each script and adds a sudoers entry" {
  local source_dir="$BATS_TEST_TMPDIR/privileged-scripts"
  local scripts_dir="$BATS_TEST_TMPDIR/opt-scripts"
  local sudoers_file="$BATS_TEST_TMPDIR/sudoers.d-panel"
  mkdir -p "$source_dir" "$scripts_dir"
  : > "$sudoers_file"
  printf '#!/usr/bin/env bash\necho hi\n' > "$source_dir/create-site.sh"
  chmod +x "$source_dir/create-site.sh"

  run sync_privileged_scripts "$source_dir" "$scripts_dir" "$sudoers_file"

  [ "$status" -eq 0 ]
  [ -f "$scripts_dir/create-site.sh" ]
  [ "$(_file_mode "$scripts_dir/create-site.sh")" = "700" ]
  run cat "$sudoers_file"
  [[ "$output" == *"${scripts_dir}/create-site.sh"* ]]
}

@test "sync_privileged_scripts copies multiple scripts, each mode 700 with its own sudoers entry" {
  local source_dir="$BATS_TEST_TMPDIR/privileged-scripts-multi"
  local scripts_dir="$BATS_TEST_TMPDIR/opt-scripts-multi"
  local sudoers_file="$BATS_TEST_TMPDIR/sudoers.d-panel-multi"
  mkdir -p "$source_dir" "$scripts_dir"
  : > "$sudoers_file"
  printf '#!/usr/bin/env bash\necho hi\n' > "$source_dir/create-site.sh"
  printf '#!/usr/bin/env bash\necho bye\n' > "$source_dir/delete-site.sh"
  chmod +x "$source_dir/create-site.sh" "$source_dir/delete-site.sh"

  run sync_privileged_scripts "$source_dir" "$scripts_dir" "$sudoers_file"

  [ "$status" -eq 0 ]
  [ -f "$scripts_dir/create-site.sh" ]
  [ -f "$scripts_dir/delete-site.sh" ]
  [ "$(_file_mode "$scripts_dir/create-site.sh")" = "700" ]
  [ "$(_file_mode "$scripts_dir/delete-site.sh")" = "700" ]
  run cat "$sudoers_file"
  [[ "$output" == *"${scripts_dir}/create-site.sh"* ]]
  [[ "$output" == *"${scripts_dir}/delete-site.sh"* ]]
}

@test "sync_privileged_scripts does nothing when the source directory is absent" {
  local scripts_dir="$BATS_TEST_TMPDIR/opt-scripts-2"
  local sudoers_file="$BATS_TEST_TMPDIR/sudoers.d-panel-2"
  mkdir -p "$scripts_dir"
  : > "$sudoers_file"

  run sync_privileged_scripts "$BATS_TEST_TMPDIR/does-not-exist" "$scripts_dir" "$sudoers_file"

  [ "$status" -eq 0 ]
  run cat "$sudoers_file"
  [ -z "$output" ]
}
