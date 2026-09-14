# TESTING.md — Vérification manuelle de l'installateur

Procédure à exécuter sur une VM Ubuntu/Debian jetable (droplet, Multipass, Vagrant).
Aucune étape ici n'est automatisée en CI (décision actée dans la spec du
sous-projet Installateur) : c'est la seule source de vérité pour les parties
qui mutent l'état système.

## Dossier de scripts privilégiés et sudoers (Task 3)

1. Après exécution de `setup_scripts_dir /opt/panel/scripts` :
   - `stat -c "%U:%G %a" /opt/panel/scripts` doit afficher `root:root 700`.
   - `sudo -u panel touch /opt/panel/scripts/test` doit échouer (Permission denied).
2. Après `setup_sudoers_file /etc/sudoers.d/panel` :
   - `stat -c "%U:%G %a" /etc/sudoers.d/panel` doit afficher `root:root 440`.
   - Le fichier doit être vide (`test -s /etc/sudoers.d/panel` retourne faux).
3. Après `add_sudoers_entry` pour un script donné :
   - `sudo -u panel sudo -n /opt/panel/scripts/<script>.sh` doit s'exécuter sans
     demander de mot de passe.
   - `sudo -u panel sudo -n /bin/bash` doit échouer (pas d'accès sudo en dehors
     des scripts listés).

## Paquets système (Task 4)

Avant `install_base_packages`, `ensure_git_installed` doit avoir rendu `git`
disponible (`command -v git`) puisque le gate initial (Task 2) en dépend et
s'exécute avant l'installation des paquets.

`install_base_packages` ajoute d'abord le dépôt tiers PHP approprié
(`add_php_repository` : `ppa:ondrej/php` sur Ubuntu, `packages.sury.org` sur
Debian — les paquets `php8.4-*` ne sont pas dans les dépôts par défaut
d'Ubuntu 22.04+/24.04+ ni de Debian 12+) avant d'installer les paquets `apt`.

Après `install_base_packages` :
- `nginx -v`, `php8.4 -v`, `mysql --version`, `composer --version`, `certbot --version`,
  `node --version` doivent tous répondre sans erreur.
- `systemctl is-active nginx`, `systemctl is-active php8.4-fpm`, `systemctl is-active mysql`
  doivent tous afficher `active`.

## User système panel (Task 5)

Après `create_panel_user` :
- `id panel` affiche l'utilisateur avec le bon shell : `getent passwd panel` doit
  se terminer par `/usr/sbin/nologin`.
- `su - panel` doit refuser toute connexion interactive.
- `stat -c "%U:%G %a" /opt/panel` doit afficher `root:root 755` — **`panel` ne
  doit jamais posséder son propre répertoire home**, sinon il pourrait
  renommer/recréer `/opt/panel/scripts` malgré son verrou `root:root 700`
  (le droit de modification d'une entrée dépend du répertoire parent, pas de
  l'entrée elle-même). Vérifié après création du user, avant tout déploiement.

## Déploiement de l'app panel (Task 6)

Prérequis : servir `tests/fixtures/fake-panel-app` comme dépôt git local
(`cd tests/fixtures/fake-panel-app && git init && git add -A && git commit -m fixture`)
puis cloner via `file://` à la place d'une vraie URL SSH pour ce test manuel.

Après `deploy_panel_app` :
- `/opt/panel/app/.env` contient les bonnes valeurs `DB_DATABASE`, `DB_USERNAME`,
  `APP_URL`.
- `stat -c "%a" /opt/panel/app/.env` doit afficher `640` (pas world-readable :
  le fichier contient le mot de passe MySQL et `APP_KEY`).
- Le fake `artisan` a bien été appelé avec `migrate --force` puis
  `panel:create-admin <email> --password=...` (visible dans les logs, puisque
  le fake artisan écrit ses arguments sur stdout).
- `/opt/panel/app` appartient à `panel:panel`.
- **Le fichier de clé passé en `--deploy-key` n'existe plus après le clone**
  (`test -f <chemin-de-la-clé>` doit être faux) : l'installateur l'efface
  activement avec `shred -u` (repli sur `rm -f` si `shred` est absent).

Note : ce test manuel utilise le fixture, pas la vraie app panel (qui n'existe
pas encore — sous-projet séparé). Refaire ce test contre le vrai repo dès qu'il
existe.

## Vhost nginx et SSL (Task 7)

Après `write_panel_vhost` :
- `nginx -t` ne rapporte aucune erreur.
- `curl -I http://<domaine>` répond (redirection ou 200) depuis une machine
  où le DNS résout déjà vers la VM de test.

Après `issue_panel_certificate` :
- `curl -I https://<domaine>` répond avec un certificat valide.
- Si le DNS ne pointe pas encore vers la VM, `issue_panel_certificate` doit
  échouer proprement avec le message loggé ci-dessus, pas planter le script
  sans explication.

## Pool PHP-FPM dédié

Après `setup_panel_php_pool` :
- `/etc/php/8.4/fpm/pool.d/panel.conf` existe et contient `user = panel` (et
  `group = panel`, `listen = /run/php/php8.4-fpm-panel.sock`).
- `systemctl is-active php8.4-fpm` affiche `active` après le reload déclenché
  par cette fonction.
- Le panel répond normalement une fois déployé (vhost + pool en place).
- `ps -o user= -C php-fpm8.4 | sort -u` doit inclure `panel` dans la liste des
  users sous lesquels tournent les processus PHP-FPM — preuve que le panel
  tourne bien sous son pool dédié et pas sous le pool par défaut (`www-data`).

## Bout en bout (Task 8)

Sur une VM Ubuntu/Debian jetable avec un domaine dont le DNS pointe déjà
vers elle :

**Important — la clé passée en `--deploy-key` est supprimée par l'installateur**
(`shred -u` après le clone, voir Task 6) : utilisez toujours une **copie
jetable** de la clé, jamais le fichier de clé personnel/permanent de l'admin
(ex: pas directement `/root/.ssh/id_ed25519`). Exemple : `cp /root/.ssh/id_ed25519
/root/.ssh/deploy-key-disposable` puis passez cette copie en `--deploy-key`.

```bash
./install.sh \
  --domain=panel.example.com \
  --repo-url=file:///path/to/tests/fixtures/fake-panel-app \
  --deploy-key=/root/.ssh/deploy-key-disposable \
  --admin-email=admin@example.com
```

Vérifier, dans l'ordre des tâches précédentes : paquets actifs, user `panel`
en nologin, `/opt/panel/scripts` verrouillé, pool PHP-FPM dédié actif, `.env`
correct (et en `640`), clé de déploiement supprimée après le clone, vhost +
certificat valides, message de résumé final affiché avec le mot de passe
admin généré.

Note importante sur la couverture de ce test : ce run utilise
`--repo-url=file:///...` vers le fixture, qui **ne passe jamais par SSH**
(le transport `file://` ignore `GIT_SSH_COMMAND`) — il ne teste donc que la
mécanique d'installation (clone, `.env`, composer, migrations, admin), pas le
chemin SSH du gate. Un vrai test de bout en bout contre le vrai repo de l'app
panel (une fois qu'il existe, dans un sous-projet séparé) doit aussi être
exécuté avec la vraie clé de déploiement, via SSH, pour prouver que le
chemin SSH du gate fonctionne réellement de bout en bout.

## Test négatif : clé invalide

Ce test doit prouver que le gate **rejette une clé non autorisée**, pas
seulement qu'il détecte un fichier manquant — un fichier de clé inexistant
échouerait de la même façon pour une tout autre raison (erreur de lecture du
fichier) sans jamais exercer la logique d'autorisation côté serveur distant.

```bash
# Génère une clé SSH valide syntaxiquement, mais jamais enregistrée comme clé
# de déploiement autorisée sur le vrai repo.
ssh-keygen -t ed25519 -f /tmp/unregistered-key -N ""

./install.sh \
  --domain=panel.example.com \
  --repo-url=git@github.com:agency/panel-app.git \
  --deploy-key=/tmp/unregistered-key \
  --admin-email=admin@example.com
```

Attendu : le serveur distant (la vraie URL du repo, pas le fixture `file://`)
rejette la clé (elle n'est pas dans les clés de déploiement autorisées), le
script s'arrête immédiatement après le message "Deploy key rejected. Aborting
— nothing was installed." et **aucun** paquet n'a été installé (`dpkg -l |
grep nginx` ne doit rien retourner sur une VM vierge).

## Bootstrap public (`bootstrap.sh`)

`bootstrap.sh` est le point d'entrée pensé pour la distribution publique
(hébergé sur un domaine perso, ou servi directement depuis le repo GitHub
public `ranel-installer`). Il télécharge le reste du repo dans un dossier
temporaire, demande la clé de déploiement de façon interactive (collée par
l'admin, jamais passée en argument), puis délègue à `install.sh` exactement
comme le test de bout en bout ci-dessus.

**Invocation correcte** (comme Homebrew — la substitution de commande laisse
stdin connecté au terminal) :

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/RobinThijsen/ranel-installer/main/bootstrap.sh)" -- \
  --domain=panel.example.com \
  --repo-url=git@github.com:agency/panel-app.git \
  --admin-email=admin@example.com
```

**À vérifier manuellement :**

1. **Garde-fou stdin non interactif** : `echo "" | bash bootstrap.sh` doit
   échouer immédiatement avec un message expliquant d'utiliser
   `bash -c "$(curl ...)"` plutôt que `curl ... | bash` — ne doit rien
   télécharger, rien demander.
2. **Téléchargement** : sur une machine avec `curl`/`tar`, lancer
   `RANEL_INSTALLER_ARCHIVE_URL=<url-tarball> bash -c "$(cat bootstrap.sh)"`
   (ou héberger un tarball de test) et vérifier que le dossier temporaire
   contient bien `install.sh` et `lib/`.
3. **Saisie de la clé** : coller le contenu d'une clé de test, terminer par
   `EOF` sur sa propre ligne ; vérifier que le fichier temporaire créé
   contient exactement le contenu collé, en `600`.
4. **Nettoyage** : après une exécution (succès ou échec), vérifier que le
   dossier temporaire du repo téléchargé et le fichier de clé temporaire
   n'existent plus (`trap cleanup EXIT` doit s'exécuter dans tous les cas,
   y compris un échec du gate).
5. **Bout en bout** : lancer l'invocation correcte ci-dessus contre une VM
   jetable et un vrai repo — vérifie que tout le flux `install.sh` documenté
   plus haut se déroule normalement une fois la clé collée.
