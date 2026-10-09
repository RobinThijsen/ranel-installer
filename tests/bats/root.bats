# The two entry points refuse to run as a normal user. Worth its own file:
# the installer is deliberately not idempotent, so a forgotten sudo costs a
# whole server, and both entry points must say so before doing anything.

@test "bootstrap.sh refuses a normal user before downloading anything" {
  [ "$(id -u)" -ne 0 ] || skip "lancé en root"

  run "$BATS_TEST_DIRNAME/../../bootstrap.sh" --domain=panel.example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"en root"* ]] || return 1
  [[ "$output" == *"Rien n'a été téléchargé"* ]] || return 1
  # no terminal requirement any more: there is no key to paste, so
  # `curl | bash` is a supported form and must not be rejected
  [[ "$output" != *"curl ... | bash"* ]] || return 1
}

@test "install.sh refuses a normal user before opening its log file" {
  [ "$(id -u)" -ne 0 ] || skip "lancé en root"

  run "$BATS_TEST_DIRNAME/../../install.sh" --domain=panel.example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"en root"* ]] || return 1
  # the cryptic redirection error is what this guard exists to avoid
  [[ "$output" != *"Permission denied"* ]] || return 1
  [ ! -f /var/log/panel-install.log ]
}
