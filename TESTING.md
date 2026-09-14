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

## Déploiement de l'app panel (Task 6)

Prérequis : servir `tests/fixtures/fake-panel-app` comme dépôt git local
(`cd tests/fixtures/fake-panel-app && git init && git add -A && git commit -m fixture`)
puis cloner via `file://` à la place d'une vraie URL SSH pour ce test manuel.

Après `deploy_panel_app` :
- `/opt/panel/app/.env` contient les bonnes valeurs `DB_DATABASE`, `DB_USERNAME`,
  `APP_URL`.
- Le fake `artisan` a bien été appelé avec `migrate --force` puis
  `panel:create-admin <email>` (visible dans les logs, puisque le fake artisan
  écrit ses arguments sur stdout).
- `/opt/panel/app` appartient à `panel:panel`.

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

## Bout en bout (Task 8)

Sur une VM Ubuntu/Debian jetable avec un domaine dont le DNS pointe déjà
vers elle :

```bash
./install.sh \
  --domain=panel.example.com \
  --repo-url=file:///path/to/tests/fixtures/fake-panel-app \
  --deploy-key=/root/.ssh/id_ed25519 \
  --admin-email=admin@example.com
```

Vérifier, dans l'ordre des tâches précédentes : paquets actifs, user `panel`
en nologin, `/opt/panel/scripts` verrouillé, `.env` correct, vhost + certificat
valides, message de résumé final affiché.

## Test négatif : clé invalide

```bash
./install.sh \
  --domain=panel.example.com \
  --repo-url=git@github.com:agency/panel-app.git \
  --deploy-key=/root/.ssh/nonexistent-key \
  --admin-email=admin@example.com
```

Attendu : le script s'arrête immédiatement après le message "Deploy key
rejected. Aborting — nothing was installed." et **aucun** paquet n'a été
installé (`dpkg -l | grep nginx` ne doit rien retourner sur une VM vierge).
