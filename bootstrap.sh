#!/usr/bin/env bash
# bootstrap.sh — point d'entrée public :
#
#   curl -fsSL <url-de-ce-fichier> | sudo bash -s -- \
#     --domain=panel.example.com --admin-email=admin@example.com
#
# ou, si l'on préfère lire le script avant qu'il ne tourne :
#
#   bash -c "$(curl -fsSL <url-de-ce-fichier>)" -- --domain=… --admin-email=…
#
# Les deux formes marchent. Ça n'a pas toujours été le cas : l'installateur
# demandait de coller une clé de déploiement, donc il lui fallait un vrai
# terminal — que `curl ... | bash` n'a pas, le pipe occupant déjà stdin. Le
# panel s'installe maintenant depuis une archive versionnée : plus de clé,
# plus de saisie, plus de contrainte.
set -euo pipefail

# Avant tout le reste : l'installateur a besoin de root (apt, mysql, /opt,
# sudoers) et n'est volontairement pas idempotent. Échouer à mi-chemin
# coûte un serveur entier, donc on refuse immédiatement.
if [ "$(id -u)" -ne 0 ]; then
  echo "Erreur : lance l'installation en root (sudo -i, puis relance la commande). Rien n'a été téléchargé." >&2
  exit 1
fi

REPO_ARCHIVE_URL="${RANEL_INSTALLER_ARCHIVE_URL:-https://github.com/RobinThijsen/ranel-installer/archive/refs/heads/main.tar.gz}"

tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

echo "Téléchargement de l'installateur..." >&2
curl -fsSL "$REPO_ARCHIVE_URL" | tar xz -C "$tmp_dir" --strip-components=1

"$tmp_dir/install.sh" "$@"
