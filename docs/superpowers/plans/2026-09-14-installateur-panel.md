# Installateur Panel — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Pas de git dans ce projet.** L'utilisateur a une règle globale interdisant à
> Claude d'utiliser git pour son propre workflow (staging, commits, branches,
> worktrees). Les étapes "Commit" du template standard sont donc omises de ce
> plan : chaque tâche se termine dès que ses tests passent. `git` reste utilisé
> à l'intérieur du code produit (le script `install.sh` clone un repo via
> `git clone`/`git ls-remote` — c'est une fonctionnalité du produit, pas une
> action de Claude sur son propre travail) et dans les tests qui simulent ce
> comportement contre un dépôt local factice.

**Goal:** Construire `install.sh`, le script qui transforme un serveur Ubuntu/Debian neuf en serveur prêt à héberger le panel : stack de base, user système dédié, sudoers scopé, clonage/config de l'app panel (dont le code sera écrit dans un sous-projet ultérieur), vhost + SSL pour le domaine du panel.

**Architecture:** Un script bash modulaire — `install.sh` orchestre des fonctions définies dans `lib/*.sh` (une responsabilité par fichier : logging, parsing d'arguments, gate git, paquets système, user panel, dossier de scripts privilégiés + sudoers, déploiement de l'app, nginx, certbot). La logique pure (parsing, rendu de templates sudoers/nginx, validation) est testée avec `bats-core` sans avoir besoin de root ni d'un vrai serveur. Les étapes qui mutent l'état système (apt install, useradd, certbot) n'ont pas de test automatisé (décision actée dans la spec) et sont vérifiées manuellement sur une VM jetable via une procédure documentée dans `TESTING.md`, complétée au fil des tâches.

**Tech Stack:** Bash (`set -euo pipefail`), bats-core pour les tests unitaires de logique pure, apt/nginx/PHP-FPM/MySQL/Certbot comme cibles de provisioning, Docker ou une VM Ubuntu/Debian (Multipass/Vagrant/droplet jetable) pour la vérification manuelle de bout en bout.

**Spec:** [docs/superpowers/specs/2026-09-14-installateur-panel-design.md](../specs/2026-09-14-installateur-panel-design.md)

## Global Constraints

- OS cible : Ubuntu/Debian. Stack : nginx, PHP 8.4-FPM, MySQL.
- Le panel Laravel tournera en user système non privilégié `panel`, sans shell de login (`/usr/sbin/nologin`).
- Actions privilégiées uniquement via des scripts wrapper fixes dans `/opt/panel/scripts/` (root:root, `700`), listés nommément (jamais de wildcard) dans `/etc/sudoers.d/panel` avec `NOPASSWD`.
- Pas de SSH local vers localhost.
- Pas de step-up par mot de passe humain : NOPASSWD assumé.
- La clé de déploiement git n'est jamais persistée sur disque après le clone.
- Gate initial obligatoire : validation de la clé git (`git ls-remote`) avant toute autre action système. Échec → abort, rien d'installé.
- Pas d'idempotence en v1 : un échec partiel impose de repartir d'un serveur propre (documenté explicitement dans les messages d'erreur).
- Pas de CI automatisée en v1 : vérification manuelle sur VM jetable, documentée dans `TESTING.md`.

---

## File Structure

```
install.sh                          — point d'entrée, orchestration séquentielle
lib/log.sh                          — log_info/log_error, écriture dans /var/log/panel-install.log
lib/args.sh                         — parse_install_args : lit les arguments CLI en variables globales
lib/gate.sh                         — validate_git_key : vérifie la clé de déploiement avant tout le reste
lib/packages.sh                     — install_base_packages : apt install nginx/PHP 8.4-FPM/MySQL/Composer/Node/Certbot
lib/user.sh                         — create_panel_user : crée le user système `panel`
lib/scripts_dir.sh                  — setup_scripts_dir, render_sudoers_line, add_sudoers_entry
lib/deploy.sh                       — deploy_panel_app : clone, .env, composer install, migrations, admin
lib/nginx.sh                        — render_panel_vhost, write_panel_vhost
lib/ssl.sh                          — issue_panel_certificate : appel Certbot pour le domaine du panel
tests/bats/log.bats
tests/bats/args.bats
tests/bats/gate.bats
tests/bats/scripts_dir.bats
tests/bats/deploy.bats
tests/bats/nginx.bats
tests/fixtures/fake-git-bin/git     — faux binaire `git` utilisé par les tests de gate.sh
tests/fixtures/fake-panel-app/      — dépôt local factice respectant le contrat attendu par deploy.sh
TESTING.md                          — procédure de vérification manuelle sur VM, complétée à chaque tâche
```

**Contrat attendu de la future app panel** (documenté ici pour que `deploy.sh` ait quelque chose de stable à cibler, même si l'app réelle sera écrite dans un sous-projet séparé) :
- Un `composer.json` à la racine du repo.
- Un exécutable `artisan` à la racine.
- Une commande Artisan `panel:create-admin {email} {--password=}` qui crée le compte admin (code de sortie `0` si succès).
- Un fichier `.env.example` à la racine, utilisé comme base pour générer le `.env` réel (l'installateur y injecte `APP_KEY`, les identifiants DB, et `APP_URL`).

---

### Task 1: Logging et parsing des arguments

**Files:**
- Create: `lib/log.sh`
- Create: `lib/args.sh`
- Test: `tests/bats/log.bats`
- Test: `tests/bats/args.bats`

**Interfaces:**
- Produces: `log_info(message)`, `log_error(message)` (écrivent dans `$PANEL_LOG_FILE`, par défaut `/var/log/panel-install.log`, préfixées par un horodatage ISO 8601 et le niveau).
- Produces: `parse_install_args(args...)` — remplit les variables globales `PANEL_DOMAIN`, `PANEL_REPO_URL`, `PANEL_DEPLOY_KEY_PATH`, `PANEL_ADMIN_EMAIL`. Échoue (`return 1` + message sur stderr) si un argument obligatoire manque.

- [ ] **Step 1: Écrire le test de `log.sh`**

```bash
# tests/bats/log.bats
setup() {
  export PANEL_LOG_FILE="$BATS_TEST_TMPDIR/install.log"
  source "$BATS_TEST_DIRNAME/../../lib/log.sh"
}

@test "log_info writes an INFO line with the message" {
  log_info "starting step"
  run cat "$PANEL_LOG_FILE"
  [[ "$output" == *"INFO"* ]]
  [[ "$output" == *"starting step"* ]]
}

@test "log_error writes an ERROR line with the message" {
  log_error "something broke"
  run cat "$PANEL_LOG_FILE"
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" == *"something broke"* ]]
}
```

- [ ] **Step 2: Lancer le test et vérifier qu'il échoue**

Run: `bats tests/bats/log.bats`
Expected: FAIL — `lib/log.sh: No such file or directory`

- [ ] **Step 3: Implémenter `lib/log.sh`**

```bash
#!/usr/bin/env bash
# lib/log.sh

: "${PANEL_LOG_FILE:=/var/log/panel-install.log}"

_log_write() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "${timestamp} [${level}] ${message}" >> "$PANEL_LOG_FILE"
}

log_info() {
  _log_write "INFO" "$1"
}

log_error() {
  _log_write "ERROR" "$1"
}
```

- [ ] **Step 4: Lancer le test et vérifier qu'il passe**

Run: `bats tests/bats/log.bats`
Expected: PASS (2 tests)

- [ ] **Step 5: Écrire le test de `args.sh`**

```bash
# tests/bats/args.bats
setup() {
  source "$BATS_TEST_DIRNAME/../../lib/args.sh"
}

@test "parse_install_args fills the expected globals" {
  parse_install_args \
    --domain=panel.example.com \
    --repo-url=git@github.com:agency/panel-app.git \
    --deploy-key=/tmp/fake-key \
    --admin-email=admin@example.com

  [ "$PANEL_DOMAIN" = "panel.example.com" ]
  [ "$PANEL_REPO_URL" = "git@github.com:agency/panel-app.git" ]
  [ "$PANEL_DEPLOY_KEY_PATH" = "/tmp/fake-key" ]
  [ "$PANEL_ADMIN_EMAIL" = "admin@example.com" ]
}

@test "parse_install_args fails when --domain is missing" {
  run parse_install_args \
    --repo-url=git@github.com:agency/panel-app.git \
    --deploy-key=/tmp/fake-key \
    --admin-email=admin@example.com
  [ "$status" -ne 0 ]
  [[ "$output" == *"--domain is required"* ]]
}
```

- [ ] **Step 6: Lancer le test et vérifier qu'il échoue**

Run: `bats tests/bats/args.bats`
Expected: FAIL — `lib/args.sh: No such file or directory`

- [ ] **Step 7: Implémenter `lib/args.sh`**

```bash
#!/usr/bin/env bash
# lib/args.sh

parse_install_args() {
  PANEL_DOMAIN=""
  PANEL_REPO_URL=""
  PANEL_DEPLOY_KEY_PATH=""
  PANEL_ADMIN_EMAIL=""

  for arg in "$@"; do
    case "$arg" in
      --domain=*) PANEL_DOMAIN="${arg#--domain=}" ;;
      --repo-url=*) PANEL_REPO_URL="${arg#--repo-url=}" ;;
      --deploy-key=*) PANEL_DEPLOY_KEY_PATH="${arg#--deploy-key=}" ;;
      --admin-email=*) PANEL_ADMIN_EMAIL="${arg#--admin-email=}" ;;
      *)
        echo "Unknown argument: $arg" >&2
        return 1
        ;;
    esac
  done

  [ -n "$PANEL_DOMAIN" ] || { echo "--domain is required" >&2; return 1; }
  [ -n "$PANEL_REPO_URL" ] || { echo "--repo-url is required" >&2; return 1; }
  [ -n "$PANEL_DEPLOY_KEY_PATH" ] || { echo "--deploy-key is required" >&2; return 1; }
  [ -n "$PANEL_ADMIN_EMAIL" ] || { echo "--admin-email is required" >&2; return 1; }

  return 0
}
```

- [ ] **Step 8: Lancer le test et vérifier qu'il passe**

Run: `bats tests/bats/args.bats`
Expected: PASS (2 tests)

---

### Task 2: Gate — validation de la clé de déploiement git

**Files:**
- Create: `lib/gate.sh`
- Create: `tests/fixtures/fake-git-bin/git`
- Test: `tests/bats/gate.bats`

**Interfaces:**
- Consumes: `log_info`, `log_error` (Task 1).
- Produces: `validate_git_key(repo_url, key_path)` — retourne `0` si `git ls-remote` réussit avec la clé fournie, `1` sinon. N'effectue aucune autre action système.

- [ ] **Step 1: Créer le faux binaire `git` utilisé par les tests**

```bash
# tests/fixtures/fake-git-bin/git
#!/usr/bin/env bash
# Simule `git ls-remote` : réussit si GIT_SSH_COMMAND référence une clé
# dont le nom de fichier contient "valid", échoue sinon.
if [[ "$1" == "ls-remote" ]]; then
  if [[ "$GIT_SSH_COMMAND" == *valid* ]]; then
    echo "abcd1234 HEAD"
    exit 0
  else
    echo "Permission denied (publickey)." >&2
    exit 128
  fi
fi
echo "unsupported command in fake git: $*" >&2
exit 1
```

```bash
chmod +x tests/fixtures/fake-git-bin/git
```

- [ ] **Step 2: Écrire le test de `gate.sh`**

```bash
# tests/bats/gate.bats
setup() {
  source "$BATS_TEST_DIRNAME/../../lib/log.sh"
  source "$BATS_TEST_DIRNAME/../../lib/gate.sh"
  export PANEL_LOG_FILE="$BATS_TEST_TMPDIR/install.log"
  export PATH="$BATS_TEST_DIRNAME/../fixtures/fake-git-bin:$PATH"
}

@test "validate_git_key succeeds with a valid key" {
  run validate_git_key "git@example.com:agency/panel-app.git" "/tmp/valid-key"
  [ "$status" -eq 0 ]
}

@test "validate_git_key fails with an invalid key and logs an error" {
  run validate_git_key "git@example.com:agency/panel-app.git" "/tmp/bad-key"
  [ "$status" -ne 0 ]
  run cat "$PANEL_LOG_FILE"
  [[ "$output" == *"ERROR"* ]]
}
```

- [ ] **Step 3: Lancer le test et vérifier qu'il échoue**

Run: `bats tests/bats/gate.bats`
Expected: FAIL — `lib/gate.sh: No such file or directory`

- [ ] **Step 4: Implémenter `lib/gate.sh`**

```bash
#!/usr/bin/env bash
# lib/gate.sh

validate_git_key() {
  local repo_url="$1"
  local key_path="$2"

  if GIT_SSH_COMMAND="ssh -i ${key_path} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" \
     git ls-remote "$repo_url" >/dev/null 2>&1; then
    log_info "Deploy key validated against ${repo_url}"
    return 0
  else
    log_error "Deploy key rejected by ${repo_url} — aborting before any system change"
    return 1
  fi
}
```

- [ ] **Step 5: Lancer le test et vérifier qu'il passe**

Run: `bats tests/bats/gate.bats`
Expected: PASS (2 tests)

---

### Task 3: Dossier de scripts privilégiés et sudoers

**Files:**
- Create: `lib/scripts_dir.sh`
- Test: `tests/bats/scripts_dir.bats`
- Modify: `TESTING.md` (créer si absent — première section)

**Interfaces:**
- Consumes: `log_info` (Task 1).
- Produces: `render_sudoers_line(script_path)` — retourne (via stdout) la ligne sudoers exacte pour ce script (pas de wildcard).
- Produces: `setup_scripts_dir(dir_path)` — crée le dossier avec les permissions attendues (mutation système, non testée en bats, vérifiée manuellement).
- Produces: `add_sudoers_entry(script_path, sudoers_file)` — ajoute la ligne rendue au fichier sudoers puis valide sa syntaxe avec `visudo -c -f`.

- [ ] **Step 1: Écrire le test de `render_sudoers_line`**

```bash
# tests/bats/scripts_dir.bats
setup() {
  source "$BATS_TEST_DIRNAME/../../lib/scripts_dir.sh"
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
```

- [ ] **Step 2: Lancer le test et vérifier qu'il échoue**

Run: `bats tests/bats/scripts_dir.bats`
Expected: FAIL — `lib/scripts_dir.sh: No such file or directory`

- [ ] **Step 3: Implémenter `lib/scripts_dir.sh`**

```bash
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
```

- [ ] **Step 4: Lancer le test et vérifier qu'il passe**

Run: `bats tests/bats/scripts_dir.bats`
Expected: PASS (2 tests) — sur une machine sans `visudo` (ex: macOS sans sudo installé), le test passe quand même car la validation est conditionnelle ; sur la VM Ubuntu de test manuel, `visudo` est toujours présent.

- [ ] **Step 5: Créer `TESTING.md` avec la première section de vérification manuelle**

```markdown
# TESTING.md — Vérification manuelle de l'installateur

Procédure à exécuter sur une VM Ubuntu/Debian jetable (droplet, Multipass, Vagrant).
Aucune étape ici n'est automatisée en CI (décision actée dans la spec du
sous-projet Installateur) : c'est la seule source de vérité pour les parties
qui mutent l'état système.

## Dossier de scripts privilégiés et sudoers (Task 3)

1. Après exécution de `setup_scripts_dir /opt/panel/scripts` :
   - `stat -c "%U:%G %a" /opt/panel/scripts` doit afficher `root:root 700`.
   - `sudo -u panel touch /opt/panel/scripts/test` doit échouer (Permission denied).
2. Après `add_sudoers_entry` pour un script donné :
   - `sudo -u panel sudo -n /opt/panel/scripts/<script>.sh` doit s'exécuter sans
     demander de mot de passe.
   - `sudo -u panel sudo -n /bin/bash` doit échouer (pas d'accès sudo en dehors
     des scripts listés).
```

- [ ] **Step 6: Confirmer visuellement que `TESTING.md` est bien formé**

Run: `cat TESTING.md`
Expected: le contenu ci-dessus s'affiche sans erreur de rendu Markdown évidente (titres, listes numérotées).

---

### Task 4: Installation des paquets système

**Files:**
- Create: `lib/packages.sh`
- Modify: `TESTING.md` (ajouter la section de vérification pour cette tâche)

**Interfaces:**
- Consumes: `log_info` (Task 1).
- Produces: `install_base_packages()` — installe nginx, PHP 8.4-FPM, MySQL, Composer, Node.js, Certbot via apt. Mutation système complète, pas de test bats (rien à unitester : c'est un appel direct à `apt-get`).

- [ ] **Step 1: Implémenter `lib/packages.sh`**

```bash
#!/usr/bin/env bash
# lib/packages.sh

install_base_packages() {
  log_info "Updating apt package index"
  apt-get update -y

  log_info "Installing nginx, MySQL, Composer prerequisites, Node.js, Certbot"
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    nginx \
    mysql-server \
    php8.4-fpm php8.4-mysql php8.4-cli php8.4-xml php8.4-mbstring php8.4-curl \
    unzip curl \
    certbot python3-certbot-nginx \
    nodejs npm

  if ! command -v composer >/dev/null 2>&1; then
    log_info "Installing Composer"
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
  fi

  log_info "Base packages installed"
}
```

- [ ] **Step 2: Ajouter la section de vérification manuelle correspondante à `TESTING.md`**

```markdown
## Paquets système (Task 4)

Après `install_base_packages` :
- `nginx -v`, `php8.4 -v`, `mysql --version`, `composer --version`, `certbot --version`,
  `node --version` doivent tous répondre sans erreur.
- `systemctl is-active nginx`, `systemctl is-active php8.4-fpm`, `systemctl is-active mysql`
  doivent tous afficher `active`.
```

- [ ] **Step 3: Confirmer visuellement l'ajout**

Run: `cat TESTING.md`
Expected: la nouvelle section "Paquets système (Task 4)" apparaît à la suite de la précédente.

---

### Task 5: Création du user système `panel`

**Files:**
- Create: `lib/user.sh`
- Modify: `TESTING.md`

**Interfaces:**
- Consumes: `log_info` (Task 1).
- Produces: `create_panel_user()` — crée le user `panel` avec `/usr/sbin/nologin`, idempotent au sens shell (`id panel` avant création pour éviter une erreur `useradd` si relancé manuellement — ce n'est pas l'idempotence complète du script refusée dans la spec, juste éviter un crash bête sur cette étape isolée).

- [ ] **Step 1: Implémenter `lib/user.sh`**

```bash
#!/usr/bin/env bash
# lib/user.sh

create_panel_user() {
  if id panel >/dev/null 2>&1; then
    log_info "System user 'panel' already exists, skipping creation"
    return 0
  fi

  useradd --system --shell /usr/sbin/nologin --home-dir /opt/panel --create-home panel
  log_info "Created system user 'panel' (nologin)"
}
```

- [ ] **Step 2: Ajouter la section de vérification manuelle à `TESTING.md`**

```markdown
## User système panel (Task 5)

Après `create_panel_user` :
- `id panel` affiche l'utilisateur avec le bon shell : `getent passwd panel` doit
  se terminer par `/usr/sbin/nologin`.
- `su - panel` doit refuser toute connexion interactive.
```

- [ ] **Step 3: Confirmer visuellement l'ajout**

Run: `cat TESTING.md`
Expected: la section "User système panel (Task 5)" est présente.

---

### Task 6: Déploiement de l'app panel (clone, DB, .env, migrations, admin)

**Files:**
- Create: `lib/deploy.sh`
- Create: `tests/fixtures/fake-panel-app/composer.json`
- Create: `tests/fixtures/fake-panel-app/artisan`
- Create: `tests/fixtures/fake-panel-app/.env.example`
- Test: `tests/bats/deploy.bats`
- Modify: `TESTING.md`

**Interfaces:**
- Consumes: `log_info`, `log_error` (Task 1).
- Produces: `render_panel_env(env_example_path, db_name, db_user, db_password, app_url, app_key)` — retourne (stdout) le contenu du `.env` généré à partir de `.env.example`, avec les clés `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`, `APP_URL`, `APP_KEY` remplacées/ajoutées. Pure, testable sans root.
- Produces: `deploy_panel_app(repo_url, key_path, target_dir, domain, db_name, db_user, db_password)` — clone le repo, écrit le `.env` via `render_panel_env`, lance `composer install`, `php artisan migrate --force`, `php artisan panel:create-admin`. Mutation système, testée manuellement contre `tests/fixtures/fake-panel-app` servi comme dépôt git local (voir `TESTING.md`).

- [ ] **Step 1: Créer le squelette de dépôt factice utilisé par les tests**

```json
// tests/fixtures/fake-panel-app/composer.json
{
  "name": "agency/fake-panel-app",
  "description": "Fixture used only to test install.sh's deploy step, not the real panel app."
}
```

```bash
# tests/fixtures/fake-panel-app/artisan
#!/usr/bin/env bash
echo "fake artisan called with: $*"
exit 0
```

```bash
chmod +x tests/fixtures/fake-panel-app/artisan
```

```
# tests/fixtures/fake-panel-app/.env.example
APP_NAME=Panel
APP_ENV=production
APP_KEY=
APP_URL=http://localhost
DB_CONNECTION=mysql
DB_DATABASE=panel
DB_USERNAME=panel
DB_PASSWORD=
```

- [ ] **Step 2: Écrire le test de `render_panel_env`**

```bash
# tests/bats/deploy.bats
setup() {
  source "$BATS_TEST_DIRNAME/../../lib/deploy.sh"
  export FIXTURE_ENV_EXAMPLE="$BATS_TEST_DIRNAME/../fixtures/fake-panel-app/.env.example"
}

@test "render_panel_env fills DB and app values from .env.example" {
  run render_panel_env "$FIXTURE_ENV_EXAMPLE" "panel_db" "panel_user" "s3cret" "https://panel.example.com" "base64:fakekey"

  [ "$status" -eq 0 ]
  [[ "$output" == *"DB_DATABASE=panel_db"* ]]
  [[ "$output" == *"DB_USERNAME=panel_user"* ]]
  [[ "$output" == *"DB_PASSWORD=s3cret"* ]]
  [[ "$output" == *"APP_URL=https://panel.example.com"* ]]
  [[ "$output" == *"APP_KEY=base64:fakekey"* ]]
}
```

- [ ] **Step 3: Lancer le test et vérifier qu'il échoue**

Run: `bats tests/bats/deploy.bats`
Expected: FAIL — `lib/deploy.sh: No such file or directory`

- [ ] **Step 4: Implémenter `lib/deploy.sh`**

```bash
#!/usr/bin/env bash
# lib/deploy.sh

render_panel_env() {
  local env_example_path="$1"
  local db_name="$2"
  local db_user="$3"
  local db_password="$4"
  local app_url="$5"
  local app_key="$6"

  sed \
    -e "s|^DB_DATABASE=.*|DB_DATABASE=${db_name}|" \
    -e "s|^DB_USERNAME=.*|DB_USERNAME=${db_user}|" \
    -e "s|^DB_PASSWORD=.*|DB_PASSWORD=${db_password}|" \
    -e "s|^APP_URL=.*|APP_URL=${app_url}|" \
    -e "s|^APP_KEY=.*|APP_KEY=${app_key}|" \
    "$env_example_path"
}

deploy_panel_app() {
  local repo_url="$1"
  local key_path="$2"
  local target_dir="$3"
  local domain="$4"
  local db_name="$5"
  local db_user="$6"
  local db_password="$7"

  log_info "Cloning panel app from ${repo_url} into ${target_dir}"
  GIT_SSH_COMMAND="ssh -i ${key_path} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" \
    git clone --depth 1 "$repo_url" "$target_dir"

  local app_key
  app_key="base64:$(openssl rand -base64 32)"

  render_panel_env "${target_dir}/.env.example" "$db_name" "$db_user" "$db_password" \
    "https://${domain}" "$app_key" > "${target_dir}/.env"

  log_info "Running composer install"
  (cd "$target_dir" && composer install --no-dev --optimize-autoloader)

  log_info "Running database migrations"
  (cd "$target_dir" && php artisan migrate --force)

  log_info "Creating initial admin account"
  (cd "$target_dir" && php artisan panel:create-admin "$PANEL_ADMIN_EMAIL")

  chown -R panel:panel "$target_dir"
  log_info "Panel app deployed to ${target_dir}"
}
```

- [ ] **Step 5: Lancer le test et vérifier qu'il passe**

Run: `bats tests/bats/deploy.bats`
Expected: PASS (1 test)

- [ ] **Step 6: Ajouter la section de vérification manuelle à `TESTING.md`**

```markdown
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
```

- [ ] **Step 7: Confirmer visuellement l'ajout**

Run: `cat TESTING.md`
Expected: la section "Déploiement de l'app panel (Task 6)" est présente, avec la note sur le fixture.

---

### Task 7: Vhost nginx et certificat SSL pour le domaine du panel

**Files:**
- Create: `lib/nginx.sh`
- Create: `lib/ssl.sh`
- Test: `tests/bats/nginx.bats`
- Modify: `TESTING.md`

**Interfaces:**
- Consumes: `log_info` (Task 1).
- Produces: `render_panel_vhost(domain, app_root)` — retourne (stdout) la config nginx complète pour ce domaine, pointant vers `app_root/public`. Pure, testable.
- Produces: `write_panel_vhost(domain, app_root, sites_available_dir, sites_enabled_dir)` — écrit le fichier et crée le lien symbolique ; mutation système, vérifiée manuellement.
- Produces: `issue_panel_certificate(domain)` — appelle `certbot --nginx -d <domain>` ; mutation système, vérifiée manuellement.

- [ ] **Step 1: Écrire le test de `render_panel_vhost`**

```bash
# tests/bats/nginx.bats
setup() {
  source "$BATS_TEST_DIRNAME/../../lib/nginx.sh"
}

@test "render_panel_vhost points server_name and root at the given domain and app" {
  run render_panel_vhost "panel.example.com" "/opt/panel/app"

  [ "$status" -eq 0 ]
  [[ "$output" == *"server_name panel.example.com;"* ]]
  [[ "$output" == *"root /opt/panel/app/public;"* ]]
  [[ "$output" == *"fastcgi_pass unix:/run/php/php8.4-fpm.sock;"* ]]
}
```

- [ ] **Step 2: Lancer le test et vérifier qu'il échoue**

Run: `bats tests/bats/nginx.bats`
Expected: FAIL — `lib/nginx.sh: No such file or directory`

- [ ] **Step 3: Implémenter `lib/nginx.sh`**

```bash
#!/usr/bin/env bash
# lib/nginx.sh

render_panel_vhost() {
  local domain="$1"
  local app_root="$2"

  cat <<EOF
server {
    listen 80;
    server_name ${domain};
    root ${app_root}/public;

    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.4-fpm.sock;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF
}

write_panel_vhost() {
  local domain="$1"
  local app_root="$2"
  local sites_available_dir="${3:-/etc/nginx/sites-available}"
  local sites_enabled_dir="${4:-/etc/nginx/sites-enabled}"

  local vhost_path="${sites_available_dir}/panel.conf"
  render_panel_vhost "$domain" "$app_root" > "$vhost_path"
  ln -sf "$vhost_path" "${sites_enabled_dir}/panel.conf"

  nginx -t
  systemctl reload nginx
  log_info "Nginx vhost written for ${domain} and reloaded"
}
```

- [ ] **Step 4: Lancer le test et vérifier qu'il passe**

Run: `bats tests/bats/nginx.bats`
Expected: PASS (1 test)

- [ ] **Step 5: Implémenter `lib/ssl.sh`**

```bash
#!/usr/bin/env bash
# lib/ssl.sh

issue_panel_certificate() {
  local domain="$1"

  log_info "Requesting Let's Encrypt certificate for ${domain}"
  if ! certbot --nginx -d "$domain" --non-interactive --agree-tos -m "$PANEL_ADMIN_EMAIL" --redirect; then
    log_error "Certbot failed for ${domain} — check that DNS already points to this server"
    return 1
  fi
  log_info "Certificate issued for ${domain}"
}
```

- [ ] **Step 6: Ajouter la section de vérification manuelle à `TESTING.md`**

```markdown
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
```

- [ ] **Step 7: Confirmer visuellement l'ajout**

Run: `cat TESTING.md`
Expected: la section "Vhost nginx et SSL (Task 7)" est présente.

---

### Task 8: Orchestration finale (`install.sh`) et test de bout en bout

**Files:**
- Create: `install.sh`
- Modify: `TESTING.md` (section finale : procédure complète + test négatif)

**Interfaces:**
- Consumes: toutes les fonctions des tâches 1 à 7 (`parse_install_args`, `validate_git_key`, `install_base_packages`, `create_panel_user`, `setup_scripts_dir`, `deploy_panel_app`, `write_panel_vhost`, `issue_panel_certificate`, `log_info`, `log_error`).
- Produces: le script exécutable `install.sh`, point d'entrée unique documenté dans la spec.

- [ ] **Step 1: Implémenter `install.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"
# shellcheck source=lib/args.sh
source "${SCRIPT_DIR}/lib/args.sh"
# shellcheck source=lib/gate.sh
source "${SCRIPT_DIR}/lib/gate.sh"
# shellcheck source=lib/packages.sh
source "${SCRIPT_DIR}/lib/packages.sh"
# shellcheck source=lib/user.sh
source "${SCRIPT_DIR}/lib/user.sh"
# shellcheck source=lib/scripts_dir.sh
source "${SCRIPT_DIR}/lib/scripts_dir.sh"
# shellcheck source=lib/deploy.sh
source "${SCRIPT_DIR}/lib/deploy.sh"
# shellcheck source=lib/nginx.sh
source "${SCRIPT_DIR}/lib/nginx.sh"
# shellcheck source=lib/ssl.sh
source "${SCRIPT_DIR}/lib/ssl.sh"

PANEL_APP_DIR="/opt/panel/app"
PANEL_SCRIPTS_DIR="/opt/panel/scripts"
PANEL_SUDOERS_FILE="/etc/sudoers.d/panel"
PANEL_DB_NAME="panel"
PANEL_DB_USER="panel"

main() {
  parse_install_args "$@"

  log_info "Validating deploy key before touching the system"
  if ! validate_git_key "$PANEL_REPO_URL" "$PANEL_DEPLOY_KEY_PATH"; then
    echo "Deploy key rejected. Aborting — nothing was installed." >&2
    exit 1
  fi

  install_base_packages
  create_panel_user
  setup_scripts_dir "$PANEL_SCRIPTS_DIR"

  local db_password
  db_password="$(openssl rand -base64 24)"
  mysql -e "CREATE DATABASE IF NOT EXISTS ${PANEL_DB_NAME};"
  mysql -e "CREATE USER IF NOT EXISTS '${PANEL_DB_USER}'@'localhost' IDENTIFIED BY '${db_password}';"
  mysql -e "GRANT ALL PRIVILEGES ON ${PANEL_DB_NAME}.* TO '${PANEL_DB_USER}'@'localhost';"
  mysql -e "FLUSH PRIVILEGES;"

  deploy_panel_app "$PANEL_REPO_URL" "$PANEL_DEPLOY_KEY_PATH" "$PANEL_APP_DIR" \
    "$PANEL_DOMAIN" "$PANEL_DB_NAME" "$PANEL_DB_USER" "$db_password"

  write_panel_vhost "$PANEL_DOMAIN" "$PANEL_APP_DIR"
  issue_panel_certificate "$PANEL_DOMAIN"

  echo ""
  echo "Panel installed successfully."
  echo "URL: https://${PANEL_DOMAIN}"
  echo "Admin account: ${PANEL_ADMIN_EMAIL} (password set via panel:create-admin)"
}

main "$@"
```

```bash
chmod +x install.sh
```

- [ ] **Step 2: Ajouter la procédure de bout en bout et le test négatif à `TESTING.md`**

```markdown
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
```

- [ ] **Step 3: Lancer l'ensemble des tests bats pour confirmer qu'aucune régression n'a été introduite**

Run: `bats tests/bats/`
Expected: PASS (tous les tests des tâches 1, 2, 3, 6, 7 — soit 9 tests au total)

- [ ] **Step 4: Exécuter la procédure de bout en bout de `TESTING.md` sur une VM jetable**

Suivre la section "Bout en bout (Task 8)" ci-dessus intégralement, puis la
section "Test négatif : clé invalide".
Expected: les deux scénarios se comportent comme documenté.

---

## Self-Review

**Couverture de la spec :**
- Gate initial sur la clé → Task 2 + orchestré en premier dans `main()` (Task 8). ✓
- Installation paquets (nginx/PHP 8.4-FPM/MySQL/Composer/Node/Certbot) → Task 4. ✓
- User `panel` nologin → Task 5. ✓
- `/opt/panel/scripts` root:root 700 + sudoers scopé sans wildcard → Task 3. ✓
- Clone repo, DB+user MySQL dédié, `.env`, composer install, migrations, admin → Task 6 + orchestration DB dans Task 8. ✓
- Vhost nginx + Certbot pour le domaine du panel → Task 7. ✓
- Logging dans `/var/log/panel-install.log` → Task 1, utilisé dans toutes les tâches suivantes. ✓
- Pas d'idempotence complète (décision actée) → non implémentée intentionnellement, documentée dans les Global Constraints et dans le test négatif de Task 8. ✓
- Pas de CI automatisée, procédure manuelle → `TESTING.md` construit incrémentalement de Task 3 à Task 8. ✓
- Clé de déploiement jamais persistée → `deploy_panel_app` ne copie jamais la clé, l'utilise uniquement via `GIT_SSH_COMMAND` au moment du clone. ✓

**Placeholders :** aucun "TODO"/"TBD" — toutes les étapes contiennent du code réel ou une commande de vérification concrète.

**Cohérence des types/noms :** vérifié que les noms de fonctions et variables sont réutilisés à l'identique entre tâches (`PANEL_DOMAIN`, `PANEL_REPO_URL`, `PANEL_DEPLOY_KEY_PATH`, `PANEL_ADMIN_EMAIL` définis en Task 1, consommés tels quels en Task 2, 6, 7, 8 ; `render_panel_vhost`/`write_panel_vhost` cohérents entre Task 7 et Task 8 ; `deploy_panel_app` a la même signature en Task 6 et à son appel en Task 8).

**Hors scope confirmé (pas de tâche correspondante, volontairement) :** création de sites clients, SSL pour d'autres domaines que celui du panel, gestion de bases de données de sites, cron, gestion multi-serveurs, mécanisme de licence/facturation, squelette réel de l'app panel (repoussé par toi à plus tard — seul son contrat d'interface est documenté ici).
