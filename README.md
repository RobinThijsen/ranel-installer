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
d'échec, on repart d'un serveur neuf. Les deux points ci-dessous sont
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

## L'installation

En SSH **sur le serveur, en root** :

```bash
curl -fsSL https://raw.githubusercontent.com/RobinThijsen/ranel-installer/main/bootstrap.sh | bash -s -- --domain=panel.mondomaine.com --admin-email=vous@mondomaine.com
```

Si vous préférez lire le script avant qu'il ne tourne :

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/RobinThijsen/ranel-installer/main/bootstrap.sh)" -- --domain=panel.mondomaine.com --admin-email=vous@mondomaine.com
```

Les deux formes marchent. Rien à coller, aucune clé à préparer : la
version la plus récente est résolue depuis le manifeste public et son
archive est vérifiée avant d'être dépliée.

### Les options

| Option | |
|---|---|
| `--domain=` | **requis** — le domaine du panel |
| `--admin-email=` | **requis** — le compte administrateur créé, et l'adresse donnée à Let's Encrypt |
| `--version=` | une version précise (`1.0.0`) au lieu de la dernière publiée |
| `--skip-ssl` | sert le panel en HTTP, sans certificat (local uniquement) |

Comptez quelques minutes — nettement moins qu'avant, puisque ni Composer
ni npm ne tournent sur le serveur : l'archive contient déjà les
dépendances et les assets compilés. Tout est journalisé dans
`/var/log/panel-install.log`.

**Ce qui est vérifié avant la première modification du système** : que le
manifeste est lisible, que la version demandée existe, et que l'archive
téléchargée correspond à la somme de contrôle que le manifeste annonce.
Si l'un des trois échoue, rien n'a été installé.

### À la fin

```
Panel installed successfully.
Version: 1.0.0
URL: https://panel.mondomaine.com
Admin account: vous@mondomaine.com
Admin password: <mot de passe généré>
```

**Notez ce mot de passe maintenant**, il n'est affiché qu'une fois.

## Les cinq minutes qui suivent

Connectez-vous, puis, dans l'ordre :

1. **Changez le mot de passe** (Paramètres › Profil). Celui-ci a été
   affiché dans un terminal.
2. **Clé de déploiement du panel** (Paramètres › Clé de déploiement) :
   générez-la, puis ajoutez sa partie publique comme *deploy key* sur
   chaque dépôt de site à déployer. Elle ne sert qu'aux **sites** : le
   panel, lui, n'a plus besoin d'accéder à aucun dépôt.
3. **Notifications** (Paramètres › Notifications) : un serveur SMTP, puis
   activez l'envoi. Sans ça, aucune alerte ne part — ni sauvegarde en
   échec, ni certificat qui expire, ni disque qui se remplit.
4. **Sauvegardes distantes** (Paramètres › Sauvegardes distantes) : une
   destination compatible S3. Des sauvegardes qui ne quittent pas le
   serveur disparaissent avec lui.
5. **Créez un premier site** et déployez-le.

---

## Mettre le panel à jour

Depuis l'interface (Paramètres › Mise à jour), ou sur le serveur :

```bash
sudo bash -c 'cd / && /opt/panel/scripts/panel-update.sh'
```

Il lit le manifeste, télécharge la dernière version publiée, vérifie sa
somme de contrôle, la déplie à côté des autres, joue les migrations,
puis **bascule un lien symbolique**. Les paquets manquants, les scripts
privilégiés, le `sudoers`, le cron et les services suivent.

`--check` dit seulement où on en est, sans rien changer.
`--version=1.2.3` installe une version précise.

### Revenir en arrière

```bash
sudo bash -c 'cd / && /opt/panel/scripts/panel-update.sh --version=1.0.0'
```

Une version plus ancienne est reconnue comme un retour arrière : le lien
revient, et **ni les migrations ni les paquets ne sont touchés**. Une
migration a rarement de quoi se défaire, donc revenir dans le code ne
fait jamais revenir dans les données — le script le dit plutôt que de
laisser croire le contraire. Les versions encore dépliées sont aussi
proposées dans l'interface.

## Ce que l'installateur met où

| Chemin | |
|---|---|
| `/opt/panel/app` | lien symbolique vers la version servie |
| `/opt/panel/releases/<version>/` | une version dépliée (propriétaire `panel`) |
| `/opt/panel/shared/` | le `.env` et le `storage`, qui survivent aux versions |
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
| `manifeste des versions est injoignable` | pas de sortie réseau vers `raw.githubusercontent.com` |
| `ne correspond pas à sa somme de contrôle` | archive corrompue en route — relancez ; si ça persiste, signalez-le |
| `la version X n'existe pas` | voir les versions publiées dans [le manifeste](https://github.com/RobinThijsen/ranel-dist/blob/main/versions.tsv) |
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
