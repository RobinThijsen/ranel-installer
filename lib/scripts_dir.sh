#!/usr/bin/env bash
# lib/scripts_dir.sh

render_sudoers_line() {
  local script_path="$1"
  echo "panel ALL=(root) NOPASSWD: ${script_path}"
}

add_sudoers_entry() {
  local script_path="$1"
  local sudoers_file="$2"

  render_sudoers_line "$script_path" >> "$sudoers_file"

  if command -v visudo >/dev/null 2>&1; then
    visudo -c -f "$sudoers_file" >/dev/null
  fi
}

setup_scripts_dir() {
  local dir_path="$1"

  mkdir -p "$dir_path"
  chown root:root "$dir_path"
  chmod 700 "$dir_path"
  log_info "Created privileged scripts directory at ${dir_path} (root:root, 700)"
}

setup_sudoers_file() {
  local sudoers_file="$1"

  if [ ! -f "$sudoers_file" ]; then
    : > "$sudoers_file"
  fi
  chown root:root "$sudoers_file"
  chmod 440 "$sudoers_file"

  if command -v visudo >/dev/null 2>&1; then
    visudo -c -f "$sudoers_file" >/dev/null
  fi
  log_info "Created sudoers file at ${sudoers_file} (root:root, 440, empty)"
}
