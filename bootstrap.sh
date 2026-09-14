#!/usr/bin/env bash
# bootstrap.sh — point d'entrée public, pensé pour être lancé ainsi (comme Homebrew) :
#
#   bash -c "$(curl -fsSL <url-de-ce-fichier>)" -- --domain=panel.example.com \
#     --repo-url=git@github.com:agency/panel-app.git --admin-email=admin@example.com
#
# NE PAS lancer via `curl ... | bash` : le pipe consomme stdin pour transmettre
# le script à bash, donc la saisie interactive de la clé plus bas ne recevrait
# jamais rien. `bash -c "$(curl ...)"` laisse stdin connecté au terminal.
set -euo pipefail

if [ ! -t 0 ]; then
  echo "Erreur : ce script doit être lancé avec 'bash -c \"\$(curl -fsSL <url>)\"', pas avec 'curl ... | bash' (qui empêche la saisie interactive de la clé de déploiement)." >&2
  exit 1
fi

REPO_ARCHIVE_URL="${RANEL_INSTALLER_ARCHIVE_URL:-https://github.com/RobinThijsen/ranel-installer/archive/refs/heads/main.tar.gz}"

tmp_dir="$(mktemp -d)"
key_file="$(mktemp)"
chmod 600 "$key_file"

cleanup() {
  rm -rf "$tmp_dir"
  rm -f "$key_file"
}
trap cleanup EXIT

echo "Téléchargement de l'installateur..." >&2
curl -fsSL "$REPO_ARCHIVE_URL" | tar xz -C "$tmp_dir" --strip-components=1

echo "Colle le contenu de ta clé de déploiement git (clé privée), puis termine par une ligne contenant uniquement EOF :" >&2
while IFS= read -r line; do
  [ "$line" = "EOF" ] && break
  printf '%s\n' "$line" >> "$key_file"
done

"$tmp_dir/install.sh" "$@" --deploy-key="$key_file"
