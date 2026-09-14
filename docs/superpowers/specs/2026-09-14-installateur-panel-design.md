# Panel de gestion serveur — Sous-projet 1 : Installateur

Date : 2026-09-14

## Contexte du projet global

Objectif à terme : un outil interne (usage agence/équipe, pas un produit public en v1,
mais avec une piste de commercialisation à ne pas fermer) équivalent à Plesk / Laravel
Forge / CloudPanel, pour gérer l'hébergement de sites (Laravel, Prestashop, etc.) sur
des serveurs Ubuntu/Debian.

Le projet complet est trop large pour une seule spec. Il est découpé en sous-projets,
chacun avec son propre cycle spec → plan → implémentation :

1. **Installateur** (ce document)
2. Gestion des sites & déploiement Git (vhosts multi-domaines, pull, post-deploy)
3. SSL (Let's Encrypt) par domaine
4. Bases de données (création DB + users MySQL/Postgres par site)
5. Cron, monitoring, users système

## Décisions d'architecture globales (s'appliquent à tous les sous-projets)

- **Modèle self-managed, un serveur = une instance du panel.** Pas de pilotage
  multi-serveurs depuis une instance centrale. Pour gérer un 2e serveur, on installe
  une 2e instance du panel dessus.
- **Le panel Laravel tourne en user système non privilégié** (`panel`, sans shell de
  login). Aucune action privilégiée n'est exécutée en root directement par l'app.
- **Actions privilégiées via sudoers scopé** : des scripts wrapper fixes dans
  `/opt/panel/scripts/`, chacun dédié à une action précise, listés nommément (pas de
  wildcard) dans `/etc/sudoers.d/panel` avec `NOPASSWD`. Le dossier appartient à
  `root:root`, permissions `700` — `panel` peut les exécuter via `sudo` mais jamais les
  modifier (sinon la restriction sudoers est contournable).
- **Pas de SSH local vers localhost** : ça n'apporte pas d'isolation réelle sur une
  seule machine, seulement de la complexité (gestion de clés) en plus.
- **NOPASSWD retenu plutôt qu'un step-up par mot de passe humain** : décision assumée
  après discussion des alternatives (mot de passe chiffré auto-utilisé par l'app
  n'apporte presque rien contre une RCE ; step-up humain bloque l'automatisation type
  webhook). Une éventuelle restriction d'accès au panel par IP allowlist reste possible
  au niveau HTTP, indépendamment de sudoers (pas conçue dans ce document).
- **Isolation entre sites hébergés** : un user système Linux dédié + un pool PHP-FPM
  dédié par site (conçu en détail dans le sous-projet 2).
- **Stack cible v1** : Ubuntu/Debian, nginx, PHP-FPM, MySQL.
- **OS supportés explicitement** : Ubuntu 22.04+/24.04+ et Debian 12+. PHP 8.4 n'est pas
  dans les dépôts par défaut de ces versions — l'installateur ajoute le dépôt tiers
  approprié (`ppa:ondrej/php` sur Ubuntu, `packages.sury.org` sur Debian) avant
  d'installer les paquets `php8.4-*`. *(Amendement ajouté après la revue finale du
  sous-projet Installateur — la version initiale de ce document ne fixait aucune
  version d'OS alors que PHP 8.4 en dépend entièrement.)*
- **Le panel tourne réellement sous l'utilisateur `panel`, pas sous le pool PHP-FPM par
  défaut** (`www-data`) : l'installateur crée un pool PHP-FPM dédié
  (`/etc/php/8.4/fpm/pool.d/panel.conf`, `user`/`group panel`, socket
  `/run/php/php8.4-fpm-panel.sock`) et le vhost nginx du panel pointe vers ce socket.
  Sans ce pool, les entrées sudoers scopées à `panel` ne s'appliquent jamais au
  processus qui sert réellement les requêtes du panel — c'est la fondation même du
  modèle de sécurité qui serait cassée. *(Amendement ajouté après la revue finale —
  angle mort de la version initiale.)*
- **`/opt/panel` appartient à `root:root` (755), jamais à `panel`** : seul
  `/opt/panel/scripts/` (root:root, 700) et `/opt/panel/app/` (panel:panel, après
  déploiement) ont un propriétaire particulier. Si `panel` possédait `/opt/panel`
  lui-même, il pourrait renommer/recréer `/opt/panel/scripts/` (le droit de
  modification d'une entrée dépend du répertoire parent, pas de l'entrée), rendant le
  verrou `root:root 700` sur ce sous-dossier sans effet. *(Amendement ajouté après la
  revue finale.)*
- **`git` fait partie des paquets installés avant le gate**, puisque le gate
  (`git ls-remote`) en dépend. Un serveur neuf minimal ne l'inclut pas par défaut.
  *(Amendement — angle mort de la version initiale : le gate était documenté comme
  s'exécutant "avant toute action système" alors qu'il nécessite déjà un paquet
  installé.)*

## Portée de ce sous-projet

Un script bash unique (`install.sh`) qui transforme un serveur Ubuntu/Debian neuf en
serveur prêt à héberger des sites via le panel : installation de la stack de base,
création du user `panel`, mise en place du dossier de scripts privilégiés et du
sudoers associé, déploiement et configuration de l'application panel elle-même.

Hors scope de ce sous-projet : création de sites, SSL pour des sites autres que le
panel lui-même, gestion de bases de données de sites, cron, gestion multi-serveurs,
mécanisme de licence/facturation pour la distribution commerciale de la clé git
(seule la validation d'une clé fournie est traitée ici).

## Architecture / composants

- **`install.sh`** : exécuté en root, une seule fois, sur un serveur neuf.
- Installe : nginx, PHP 8.4-FPM, MySQL, Composer, Node.js (nécessaire aux futurs
  builds npm des sites gérés), Certbot.
- Crée le user système `panel` (`/usr/sbin/nologin`, pas de shell de login).
- Crée `/opt/panel/scripts/` (root:root, 700) — vide au départ, alimenté par les
  sous-projets 2 à 5 au fil de leur implémentation.
- Crée `/etc/sudoers.d/panel` (vide au départ, une ligne par script ajouté plus tard,
  chemins absolus explicites, jamais de wildcard).
- Clone le code de l'app panel dans `/opt/panel/app` depuis un repo git privé, via une
  clé de déploiement fournie par l'admin (lecture seule, pas une clé SSH personnelle).
- Crée la base MySQL du panel + un user MySQL dédié (jamais le root MySQL), génère le
  `.env`, lance `composer install` et les migrations, crée le compte admin initial.
- Configure le vhost nginx du domaine du panel, puis Certbot pour ce domaine.

## Flux d'installation (séquence)

1. L'admin lance le script en root, avec la clé de déploiement git fournie en
   paramètre (fichier temporaire ou prompt interactif — jamais en argument visible
   dans l'historique bash) et le domaine du panel.
2. **Gate initial** : le script valide la clé (`git ls-remote` sur le repo privé)
   *avant toute autre action*. Échec → abort immédiat, aucun paquet installé, aucun
   changement système. C'est le point d'ancrage pour un futur mécanisme de
   licence/paiement commercial (clé distribuée = accès autorisé à l'installation).
3. Installation des paquets système (nginx, PHP 8.4-FPM, MySQL, Composer, Node,
   Certbot) via apt.
4. Création du user système `panel`.
5. Création de `/opt/panel/scripts/` et de `/etc/sudoers.d/panel` (vides).
6. Clone du repo panel dans `/opt/panel/app` avec la clé validée à l'étape 2.
7. Création de la DB MySQL + user dédié, génération du `.env`, `composer install`,
   migrations, création du compte admin (mot de passe généré ou saisi).
8. Configuration du vhost nginx pour le domaine du panel.
9. Certbot pour ce domaine (suppose que le DNS pointe déjà vers le serveur — un DNS
   non propagé fait échouer cette étape, à documenter clairement dans le message
   d'erreur).
10. Résumé final affiché à l'admin : URL du panel, identifiants admin.

## Sécurité

- `/opt/panel/scripts/` : `root:root`, `700`. Seul root peut lire/écrire/exécuter
  directement ; `panel` exécute via `sudo` uniquement, jamais de modification possible.
- `/etc/sudoers.d/panel` : une ligne par script, chemin absolu exact, jamais de
  wildcard (un wildcard permettrait à `panel` d'exécuter n'importe quel script qu'il
  parviendrait à déposer dans le dossier via une faille ailleurs).
- User `panel` sans shell de login (`/usr/sbin/nologin`) — pas de connexion SSH
  directe possible sous ce compte.
- La clé de déploiement git n'est conservée que le temps du clone (fichier temporaire
  supprimé immédiatement après), jamais persistée sur disque après l'installation. Une
  éventuelle mise à jour du code du panel plus tard nécessitera son propre mécanisme de
  clé — hors scope ici.
- **Application effective de la suppression de la clé** : l'installateur efface
  activement (`shred -u`) le fichier de clé fourni après le clone — ce n'est pas
  seulement "l'installateur n'en fait pas de copie", mais une suppression active du
  fichier original. *(Amendement — la version initiale n'imposait que l'absence de
  copie, pas la suppression du fichier fourni.)*
- **`.env` du panel en `640` (panel:panel), pas en permissions par défaut** : contient
  le mot de passe MySQL et `APP_KEY`. *(Amendement.)*
- **Le mot de passe MySQL ne transite jamais en argument de ligne de commande**
  (visible via `ps aux`) : les commandes `mysql` de création DB/user passent par un
  heredoc, pas par `-e "... IDENTIFIED BY '...'"`. *(Amendement.)*

## Gestion des erreurs

- Script en mode strict (`set -euo pipefail`) — tout échec arrête immédiatement
  l'installation, pas d'état partiellement configuré silencieux.
- Chaque étape logge dans `/var/log/panel-install.log` (horodaté) pour diagnostic
  après coup. **La sortie complète des commandes (apt, composer, artisan, certbot,
  nginx) est aussi capturée dans ce fichier** (pas seulement les lignes de
  progression) — sinon il ne sert à rien pour diagnostiquer un échec réel.
  `log_error` écrit aussi sur stderr, pas seulement dans le fichier, pour que l'admin
  voie l'erreur immédiatement à l'écran. *(Amendement — la version initiale ne
  précisait pas que la sortie des commandes devait être capturée.)*
- **Pas d'idempotence en v1** (décision assumée) : en cas d'échec partiel, l'admin
  repart d'un serveur/image propre plutôt que de relancer le script. Documenté
  explicitement dans le message d'erreur final (via un `trap ... ERR`, pas seulement
  en théorie) — un échec qui laisse l'admin devant une sortie brute de composer ou
  certbot sans indication de reprovisionner ne respecte pas cette exigence. À revoir
  si le besoin se confirme en usage réel.
- **Le compte admin créé affiche un mot de passe généré**, passé explicitement à
  `panel:create-admin --password=`, et affiché dans le résumé final — pas seulement
  "identifiants admin" vague. *(Amendement.)*

## Tests

- Test manuel sur VM Ubuntu/Debian neuve (droplet jetable ou VM locale
  Multipass/Vagrant avec systemd) :
  - Lancer `install.sh` de bout en bout.
  - Vérifier nginx/PHP-FPM/MySQL actifs.
  - Vérifier que le panel répond en HTTPS sur son domaine et que le login admin
    fonctionne.
  - Vérifier que `/opt/panel/scripts/` est bien verrouillé (`panel` ne peut pas y
    écrire, vérifié en tentant une écriture sous ce user).
- Test négatif : clé git invalide → le script s'arrête au gate initial, aucun paquet
  n'a été installé (vérifier l'état du serveur après l'échec).
- Pas de CI automatisée en v1 (coût/latence de provisionner une VM à chaque run) —
  procédure de test manuelle documentée dans `TESTING.md`, à automatiser plus tard si
  le besoin se confirme.
