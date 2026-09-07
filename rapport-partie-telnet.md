# TP1, partie TELNET (§2)

Serveur de connexion à distance TELNET, en clair, sur la machine serveur du lab
(`10.99.0.10`). Couvre le point 2 du sujet et prépare la capture du point 7.

## Ce qu'est TELNET
Protocole de connexion à distance (port **23/TCP**) qui ouvre un **shell** sur la
machine serveur. Modèle client/serveur : `telnetd` (démon) côté serveur, `telnet`
(commande) côté client. TELNET **ne chiffre rien** : login, mot de passe et
commandes circulent en texte clair — c'est la faiblesse démontrée au §7.

## Le rôle du superdaemon inetd
`telnetd` ne tourne pas en permanence. C'est **`inetd`** qui écoute le port 23 et
lance `in.telnetd` à chaque connexion. La config se fait donc dans
`/etc/inetd.conf`, via le service nommé `telnet` résolu vers le port par
`/etc/services`.

## Choix de configuration (et pourquoi)
| Choix | Pourquoi |
|---|---|
| `inetutils-telnetd` (serveur) + `openbsd-inetd` (superdaemon) | telnetd a besoin d'un inetd pour être lancé à la demande ; le sujet parle explicitement du superdaemon `/etc/inetd.conf` |
| `tcpd` installé | la ligne telnet de Debian appelle `/usr/sbin/tcpd` (TCP wrappers) avant telnetd ; sans lui la connexion client échoue |
| `update-inetd --enable telnet` | à l'install, la ligne est posée désactivée (`#<off>#`) ; on la réactive avec l'outil qui a posé le marqueur, plutôt qu'à la main |
| Compte `tptelnet` non privilégié | la connexion telnet en `root` est bloquée par défaut (PAM / `/etc/securetty`) ; telnet réutilise les comptes système (`/etc/passwd` + `/etc/shadow`) |
| `TELNET_PORT` en variable d'environnement | permet le §4 (ports arbitraires) sans toucher au code, comme SMTP/POP |

## Comment c'est câblé dans le projet
- `serveur/Dockerfile` : installe le serveur telnet + inetd + tcpd, active telnet,
  crée le compte `tptelnet:tptelnet123`, `EXPOSE 23`.
- `serveur/entrypoint.sh` : démarre `inetd` au boot ; réécrit `/etc/services` si
  `TELNET_PORT` ≠ 23 ; annonce le service dans la bannière.
- `serveur/healthcheck.sh` : le conteneur est `unhealthy` si le port telnet
  n'écoute pas.
- `docker-compose.yml` : `TELNET_PORT: "23"` (à changer pour le §4).

## Tests
Vérifier l'écoute côté serveur :
```bash
docker compose exec serveur netstat -antp | grep ':23'   # 0.0.0.0:23 LISTEN inetd
```
Se connecter depuis le client (point 2, « d'un ordinateur sur l'autre ») :
```bash
docker compose exec client telnet 10.99.0.10
# login: tptelnet   /   password: tptelnet123
# -> on obtient un shell distant sur le serveur
```

## Point 4 : changer le port
Dans `docker-compose.yml`, service `serveur` :
```yaml
    environment:
      TELNET_PORT: "2323"
```
Puis :
```bash
docker compose up -d --force-recreate serveur
docker compose exec serveur netstat -antp | grep ':2323'
docker compose exec client telnet 10.99.0.10 2323
```
Un `nmap -sV -p- 10.99.0.10` retrouve quand même le service via sa bannière :
déplacer un port ralentit un scan, ça ne protège rien.

## Point 7 : forme du login telnet dans la capture
En telnet, la saisie part **caractère par caractère** (un paquet par touche),
avec l'écho renvoyé par le serveur. Le login/mot de passe n'apparaît pas d'un
bloc : il faut **Follow TCP Stream** dans Wireshark pour le reconstituer. À
comparer avec POP3 (`USER`/`PASS` en ASCII d'un bloc) et SMTP `AUTH LOGIN`
(base64, un encodage, pas un chiffrement).

## Tableau des faiblesses de TELNET (§7.f)
| Faiblesse | Où elle se voit | Conséquence | Contre-mesure |
|---|---|---|---|
| Login + mot de passe en clair | Follow TCP Stream de la session port 23 | Le compte système est repris tel quel | Remplacer telnet par **SSH** (port 22, chiffré) |
| Session entière en clair | Toutes les commandes et leurs sorties | Vol d'informations, injection de commandes via MITM | SSH ; réseau chiffré |
| Aucune authentification du serveur | Côté client | Un homme au milieu se fait passer pour le serveur | SSH avec vérification de la clé d'hôte |
| Compte = vrai compte système | `/etc/passwd` + `/etc/shadow` | L'identifiant capturé ouvre un accès réel à la machine | Désactiver telnet, n'exposer que SSH |
