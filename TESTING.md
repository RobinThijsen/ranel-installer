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
