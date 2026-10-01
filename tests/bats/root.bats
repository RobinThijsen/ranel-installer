# The two entry points refuse to run as a normal user. Worth its own file:
# the installer is deliberately not idempotent, so a forgotten sudo costs a
# whole server — and bootstrap.sh asks for a private key before handing over
# to install.sh, so it must refuse *before* that.

@test "bootstrap.sh refuses a normal user before downloading or asking for the key" {
  [ "$(id -u)" -ne 0 ] || skip "lancé en root"

  run "$BATS_TEST_DIRNAME/../../bootstrap.sh" --domain=panel.example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"en root"* ]] || return 1
  [[ "$output" == *"aucune clé n'a été demandée"* ]] || return 1
  # and it said so instead of talking about the terminal
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
