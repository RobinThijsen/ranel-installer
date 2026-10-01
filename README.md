# ranel-installer

Installe **ranel**, un panel d'hébergement auto-géré, sur un serveur
Ubuntu/Debian neuf : nginx, PHP-FPM, MySQL, Composer, l'app du panel, son
worker de file, son planificateur, son vhost, son certificat Let's
Encrypt et phpMyAdmin.

Ce dépôt est public pour que `bootstrap.sh` soit téléchargeable sans
authentification. L'app du panel elle-même vit dans un dépôt privé, que
l'installateur va chercher avec une clé de déploiement que vous lui
fournissez.

---

## Avant de commencer

L'installateur **n'est pas idempotent**, et c'est assumé : il refuse de
deviner dans quel état un serveur à moitié installé se trouve. En cas
d'échec, on repart d'un serveur neuf. Les trois points ci-dessous sont
donc à régler **avant** de lancer la commande.

### 1. Un serveur neuf

- **Ubuntu 24.04 LTS** (ou Debian équivalent), rien d'installé dessus.
- 1 vCPU / 2 Go de RAM suffisent pour commencer.
- Un accès **root** en SSH. L'installateur refuse de tourner autrement : il
  touche à apt, MySQL, `/opt` et `sudoers`.
- **Un serveur = une instance du panel.** Ne l'installez pas à côté d'un
  autre panel (CloudPanel, Plesk…) : les deux se disputeraient nginx,
  PHP-FPM et MySQL.

### 2. Le DNS, avant tout le reste

Un enregistrement **A** pour le domaine du panel vers l'IP du serveur :

```
panel.mondomaine.com.   A   203.0.113.10
```

Let's Encrypt valide en appelant le serveur sur ce nom : si le DNS ne
pointe pas encore, le certificat échoue. Attendez la propagation avant de
lancer l'installation (`dig +short panel.mondomaine.com`).

**Chez Cloudflare, passez l'enregistrement en « DNS only » (nuage gris).**
En mode proxied, la validation se fait contre l'edge Cloudflare et pas
contre votre serveur.

Pour un essai sans domaine, `--skip-ssl` sert le panel en HTTP simple. À
réserver au local : le panel transporte des mots de passe.

### 3. Une clé de déploiement pour le dépôt de l'app

L'installateur clone l'app du panel par SSH. Il faut donc une paire de
clés dédiée, dont vous donnerez **la partie publique à la forge** et **la
partie privée à l'installateur**.

Sur votre machine :

```bash
ssh-keygen -t ed25519 -f ~/.ssh/ranel-deploy -C "ranel deploy key" -N ""
```

Puis, sur GitHub : dépôt de l'app → *Settings* → *Deploy keys* → *Add deploy
key* → collez le contenu de `~/.ssh/ranel-deploy.pub`. **Laissez « Allow
write access » décoché** : l'installateur ne fait que lire.

La clé est validée contre le dépôt **avant** que quoi que ce soit ne soit
installé. Une clé refusée interrompt tout sans avoir touché au système.

---

## L'installation

En SSH **sur le serveur, en root** :

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/RobinThijsen/ranel-installer/main/bootstrap.sh)" -- --domain=panel.mondomaine.com --repo-url=git@github.com:VotreCompte/ranel.git --admin-email=vous@mondomaine.com
```

**N'utilisez pas `curl … | bash`.** Le pipe occupe l'entrée standard pour
transmettre le script, et la saisie de la clé privée ne recevrait jamais
rien. La forme `bash -c "$(curl …)"` laisse le terminal connecté. Le
script refuse d'ailleurs de tourner sans terminal.

Le script demande alors la clé privée :

```
Colle le contenu de ta clé de déploiement git (clé privée), puis termine
par une ligne contenant uniquement EOF :
```

Collez tout `~/.ssh/ranel-deploy`, de `-----BEGIN` à `-----END` inclus,
puis une ligne contenant exactement `EOF`. La clé va dans un fichier
temporaire en `600`, supprimé à la fin — elle ne passe jamais en argument
de commande, où `ps` la rendrait lisible par tous.

### Les options

| Option | |
|---|---|
| `--domain=` | **requis** — le domaine du panel |
| `--repo-url=` | **requis** — le dépôt SSH de l'app |
| `--admin-email=` | **requis** — le compte administrateur créé, et l'adresse donnée à Let's Encrypt |
| `--skip-ssl` | sert le panel en HTTP, sans certificat (local uniquement) |

Comptez une dizaine de minutes. Tout est journalisé dans
`/var/log/panel-install.log`.

### À la fin

```
Panel installed successfully.
URL: https://panel.mondomaine.com
Admin account: vous@mondomaine.com
Admin password: <mot de passe généré>
```

**Notez ce mot de passe maintenant**, il n'est affiché qu'une fois.

---

## Les cinq minutes qui suivent

Connectez-vous, puis, dans l'ordre :

1. **Changez le mot de passe** (Paramètres › Profil). Celui-ci a été
   affiché dans un terminal.
2. **Clé de déploiement du panel** (Paramètres › Clé de déploiement) :
   générez-la, puis ajoutez sa partie publique comme *deploy key* sur
   chaque dépôt de site à déployer. Elle est différente de celle utilisée
   pour l'installation — celle-ci sert au panel pour aller chercher le code
   des sites.
3. **Notifications** (Paramètres › Notifications) : un serveur SMTP, puis
   activez l'envoi. Sans ça, aucune alerte ne part — ni sauvegarde en
   échec, ni certificat qui expire, ni disque qui se remplit.
4. **Sauvegardes distantes** (Paramètres › Sauvegardes distantes) : une
   destination compatible S3. Des sauvegardes qui ne quittent pas le
   serveur disparaissent avec lui.
5. **Créez un premier site** et déployez-le.

---

## Mettre le panel à jour

L'installateur ne sert qu'une fois. Ensuite, sur le serveur :

```bash
sudo bash -c 'cd / && /opt/panel/scripts/panel-update.sh'
```

Il tire la dernière version de l'app, installe les paquets manquants,
joue les migrations, resynchronise les scripts privilégiés et leur
`sudoers`, puis redémarre ce qu'il faut. `--branch=<nom>` déploie une
autre branche que `main`.

---

## Ce que l'installateur met où

| Chemin | |
|---|---|
| `/opt/panel/app` | l'app du panel (propriétaire `panel`) |
| `/opt/panel/scripts` | les scripts privilégiés (`root:root 700`) |
| `/etc/sudoers.d/panel` | une ligne par script, rien d'autre |
| `/var/www/<domaine>` | les sites hébergés |
| `/var/backups/ranel` | les sauvegardes locales |
| `/var/log/panel-install.log` | le journal de l'installation |

Le panel n'a **jamais** les droits root. Il appelle, par `sudo -n`, une
liste fermée de scripts qui revalident chacun leurs arguments.

---

## Si ça échoue

Lisez `/var/log/panel-install.log` : chaque commande y est tracée en
entier. Les causes les plus fréquentes :

| Message | Cause |
|---|---|
| `Deploy key rejected` | la clé publique n'est pas (encore) *deploy key* sur le dépôt, ou l'URL n'est pas la forme SSH `git@…` |
| `doit être lancé en root` | il manque `sudo -i` |
| une erreur de certbot | le DNS ne pointe pas encore sur ce serveur, ou Cloudflare est en mode proxied |

Puis repartez d'un serveur neuf : ce script ne se rattrape pas, et il vaut
mieux dix minutes de réinstallation qu'un serveur dont personne ne connaît
l'état.

---

## Développement

```bash
bats tests/bats
```

Les parties qui mutent l'état système ne sont pas testables ainsi : elles
sont couvertes par la procédure manuelle de [TESTING.md](TESTING.md), à
dérouler sur une VM jetable.

Dans un `.bats`, toute assertion `[[ … ]]` doit se terminer par
`|| return 1` : seule la dernière commande d'un test détermine son
résultat, et une assertion `[[ … ]]` seule passe inaperçue.
