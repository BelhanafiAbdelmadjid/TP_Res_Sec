# TP1, partie Mail et POP

Serveur SMTP et POP3 en clair, dans trois conteneurs Docker sur un bridge commun.
Couvre les points 3, 4 et 6 du sujet pour la partie Mail, et prépare les captures
du point 7.

## Lancer le lab

```bash
docker compose build
docker compose up -d
docker compose ps
```

Adressage, défini dans le fichier `.env` :

| Rôle      | Conteneur      | IP          | Nom réseau              |
|-----------|----------------|-------------|-------------------------|
| Serveur   | tp1-serveur    | 10.99.0.10  | serveur, mail.tp.local  |
| Client    | tp1-client     | 10.99.0.20  | client                  |
| Attaquant | tp1-attaquant  | 10.99.0.30  | attaquant               |

### Si le réseau refuse de se créer

```
invalid pool request: Pool overlaps with other one on this address space
```

Un autre réseau Docker occupe déjà la plage. Le message ne dit pas lequel, donc
il faut chercher :

```bash
docker network ls
docker network inspect $(docker network ls -q) \
  --format '{{.Name}}  {{range .IPAM.Config}}{{.Subnet}}{{end}}'
```

Deux sorties possibles. Soit le réseau coupable appartient à un projet arrêté et
`docker network prune` le supprime. Soit il sert encore, et vous changez le
sous réseau dans `.env`, par exemple `10.42.0.0/24` avec les IP assorties. Une
seule ligne bouge, `docker-compose.yml` et exim4 suivent tout seuls.

Le lab utilise `10.99.0.0/24` plutôt que du `172.28`, parce que Docker pioche
par défaut dans `172.17.0.0/12` et `192.168.0.0/16` pour ses réseaux
automatiques. Vous tombiez pile dedans.

### Vérification de base

Les trois machines doivent se pinger, ce qui couvre le point 1 du sujet :

```bash
docker compose exec client ping -c2 10.99.0.10
docker compose exec attaquant ping -c2 10.99.0.10
```

## Test rapide

Le dossier `tests/` est monté dans le client :

```bash
docker compose exec client bash /tests/test-mail.sh
```

Avec des ports non standards :

```bash
docker compose exec client bash /tests/test-mail.sh 10.99.0.10 2525 1110
```

## Point 3.e : envoyer un mail en telnet

Depuis le client :

```
docker compose exec client telnet 10.99.0.10 25
```

Dialogue attendu, avec les réponses du serveur en commentaire :

```
                                  # 220 mail.tp.local ESMTP Exim ...
EHLO client.tp.local              # 250-mail.tp.local Hello ...
MAIL FROM:<bob@mail.tp.local>     # 250 OK
RCPT TO:<alice@mail.tp.local>     # 250 Accepted
DATA                              # 354 Enter message, ending with "."
Subject: test TP1
From: bob@mail.tp.local
To: alice@mail.tp.local

Corps du message.
.                                 # 250 OK id=1s...
QUIT                              # 221 closing connection
```

La ligne vide entre les en têtes et le corps est obligatoire. Le point seul sur
sa ligne termine le message.

Vérifier la livraison côté serveur :

```bash
docker compose exec serveur cat /var/mail/alice
docker compose exec serveur exim4 -bp        # file d'attente
docker compose exec serveur tail /var/log/exim4/mainlog
```

## Point 3.f : relire le mail en POP3

```
docker compose exec client telnet 10.99.0.10 110
```

```
                    # +OK Dovecot ready.
USER alice          # +OK
PASS alice          # +OK Logged in.
STAT                # +OK 1 512
LIST                # +OK 1 messages: / 1 512 / .
RETR 1              # +OK 512 octets, puis le message entier
DELE 1              # +OK Marked to be deleted.
QUIT                # +OK Logging out, messages deleted.
```

Détail utile pour le compte rendu : `DELE` ne supprime rien tout de suite. Il
marque le message. La suppression a lieu au `QUIT`, quand la session passe en
état UPDATE. Un `RSET` avant le `QUIT` annule les marquages.

## Point 3.d : ce qu'il faut retenir des deux protocoles

SMTP est un protocole de transfert. Il pousse un message d'une machine vers une
autre, en texte, une commande par ligne terminée par CRLF. Les réponses sont des
codes à trois chiffres. 2xx signifie accepté, 3xx attend la suite, 4xx est une
erreur temporaire et 5xx une erreur définitive. L'enveloppe SMTP, `MAIL FROM` et
`RCPT TO`, est indépendante des en têtes `From:` et `To:` écrits dans le corps.
C'est cette séparation qui rend l'usurpation d'expéditeur triviale, et il suffit
de le montrer en mettant n'importe quoi dans `MAIL FROM`.

POP3 est un protocole d'accès. Il récupère les messages déjà livrés dans la boîte
locale. Les réponses sont `+OK` ou `-ERR`. La session a trois états successifs :
AUTHORIZATION avec `USER` et `PASS`, TRANSACTION avec `STAT`, `LIST`, `RETR` et
`DELE`, puis UPDATE au `QUIT`.

## Point 4 : changer les ports

Les deux ports sont pilotés par variables d'environnement dans
`docker-compose.yml`. Aucun fichier de configuration à modifier.

```yaml
    environment:
      SMTP_PORT: "2525"
      POP3_PORT: "1110"
```

Puis :

```bash
docker compose up -d --force-recreate serveur
docker compose exec serveur netstat -antp | grep -E '2525|1110'
docker compose exec client telnet 10.99.0.10 2525
```

Côté serveur, `exim4 -bdf -oX 2525` remplace `daemon_smtp_ports` sans toucher à
la configuration générée, et Dovecot reçoit un `inet_listener` écrit au
démarrage. Sur le `-bdf` plutôt que `-bd`, voir la section dépannage.

Remarque pour le compte rendu : `nmap -sV -p- 10.99.0.10` retrouve les deux
services malgré le déplacement, parce que la bannière `220 ... ESMTP Exim` et le
`+OK Dovecot ready` les identifient immédiatement. Changer un port ralentit un
scan, ça ne protège rien.

## Note sur le STARTTLS annoncé par exim4

La bannière `EHLO` du serveur contient `250-STARTTLS`. exim4 propose donc du
chiffrement, et le journal signale qu'il utilisera un certificat auto signé
faute de mieux. Rien à corriger, mais c'est un bon point pour le compte rendu.

Le serveur offre TLS et le client ne le demande jamais. Une session telnet
enchaîne directement sur `MAIL FROM` et tout part en clair. STARTTLS est
optionnel par conception, et un homme au milieu peut même retirer la ligne
`250-STARTTLS` de la réponse pour forcer le client à rester en clair. C'est
l'attaque par déclassement, et elle explique pourquoi les ports dédiés au
transport chiffré, 465 et 995, existent en parallèle.

Si vous préférez une capture sans aucune mention de TLS, ajoutez
`MAIN_TLS_ENABLE = false` dans `/etc/exim4/exim4.conf.localmacros` puis relancez
`update-exim4.conf`. Vérifiez ensuite avec un `EHLO` que la ligne a disparu,
la macro change de nom selon les versions d'exim.

## Note sur ipopd

Le sujet suggère `ipopd` avec un indice sur `c-client.cf`. Ce paquet vient de
UW IMAP, retiré de Debian depuis plusieurs versions. `apt-cache search pop3` ne
le remonte pas sur Debian 11 et 12. Le lab utilise donc `dovecot-pop3d`, qui
parle le même POP3 sur le port 110 et convient pour toutes les questions du TP.
Mentionnez la substitution dans le rendu, c'est le genre de détail que
l'enseignant attend.

## Piège de capture pour la partie 7

Wireshark ou tcpdump lancé sur l'hôte, sur l'interface `br-xxxxxxxx` du réseau
Docker, voit tout le trafic des conteneurs sans aucune attaque. La démonstration
tombe à plat, puisque la question « quels paquets voyez vous et pourquoi »
suppose qu'un commutateur isole les flux.

Il faut capturer depuis le conteneur attaquant, sur son `eth0` :

```bash
docker compose exec attaquant tcpdump -i eth0 -n -A 'tcp port 25 or tcp port 110'
```

Avant ARP spoofing, on n'y voit que le broadcast et le trafic destiné à
l'attaquant. Après, la session client vers serveur apparaît. C'est exactement la
différence que le compte rendu doit montrer, capture avant et capture après.

## Point 7.e : forme du login dans la capture

Trois formes différentes à distinguer, c'est une question à points.

En POP3, `USER alice` et `PASS alice` circulent en ASCII brut. Le mot de passe
est lisible tel quel dans le flux TCP.

En SMTP avec `AUTH LOGIN`, l'identifiant et le mot de passe sont en base64.
C'est un encodage, pas un chiffrement, et `echo dGVzdA== | base64 -d` suffit.
Beaucoup d'étudiants écrivent « chiffré » ici et perdent le point.

En telnet, la saisie part caractère par caractère, un paquet par touche, avec
l'écho renvoyé par le serveur. Le login n'apparaît pas d'un bloc et il faut
suivre le flux avec Follow TCP Stream pour le reconstituer.

## Point 7.f : tableau des faiblesses du service Mail

| Faiblesse | Où elle se voit | Conséquence | Contre mesure |
|---|---|---|---|
| Identifiants POP3 en clair | `USER` et `PASS` dans la capture | Le compte est repris tel quel | POP3S sur 995, ou `STLS` avec `disable_plaintext_auth = yes` |
| Contenu et en têtes SMTP en clair | Phase `DATA` | Lecture du courrier et de la liste des destinataires | STARTTLS entre serveurs, chiffrement de bout en bout pour le contenu |
| Enveloppe non authentifiée | `MAIL FROM` accepté sans contrôle | Usurpation d'expéditeur en trois lignes de telnet | SPF, DKIM, DMARC, et SMTP AUTH pour la soumission |
| `AUTH LOGIN` en base64 | Phase d'authentification SMTP | Décodage immédiat, aucune protection réelle | Exiger TLS avant toute commande `AUTH` |
| Identité du serveur non vérifiée | Côté client | Un homme au milieu se fait passer pour le serveur | TLS avec validation du certificat |
| Périmètre de relais trop large | `dc_relay_nets` dans exim4 | Le serveur devient un relais ouvert | Restreindre au sous réseau, ici `10.99.0.0/24` |

## Fichiers

```
.env                          plan d'adressage, le seul endroit à modifier
docker-compose.yml            réseau et trois conteneurs
serveur/Dockerfile            exim4 + dovecot-pop3d, comptes alice et bob
serveur/update-exim4.conf.conf  configuration debconf d'exim4
serveur/99-tp.conf            POP3 en clair, mbox aligné sur exim4
serveur/entrypoint.sh         génération de config et ports variables
client/Dockerfile             telnet, netcat, arping
attaquant/Dockerfile          nmap, tcpdump, ettercap, pour le binôme attaque
tests/test-mail.sh            envoi SMTP puis relecture POP3
```

## Dépannage

`Pool overlaps with other one on this address space` : voir la section « si le
réseau refuse de se créer » plus haut. Le build est bon, seul le sous réseau est
déjà pris.

Connexion refusée sur le port 25 : vérifier `dc_local_interfaces='0.0.0.0'` dans
`update-exim4.conf.conf`. Le défaut Debian écoute sur la boucle locale et le
client ne voit rien.

`telnet: Unable to connect to remote host: Connection refused` sur le port 110,
alors que le port 25 répond : Dovecot ne tourne pas ou n'a pas créé son
écouteur. Le conteneur reste debout parce qu'exim4 continue de son côté, donc
rien ne saute aux yeux.

Le diagnostic complet en une commande :

```bash
bash tests/diag.sh
```

Deux vérifications qui séparent les cas. Si `doveconf -n` montre bien
`protocols = pop3` et l'écouteur sur le bon port, la configuration n'est pas en
cause. Si `pgrep -a dovecot` ne renvoie rien, le processus est mort au
démarrage, et il faut le journal pour savoir pourquoi.

### Le cas rencontré : exim4 -bd bloque l'entrypoint

Symptômes trompeurs, et c'est ce qui rend la panne intéressante pour le compte
rendu. `docker compose logs serveur` est **vide**, alors que l'entrypoint
affiche normalement une bannière. `pgrep -a dovecot` ne renvoie rien, mais
`/var/log/dovecot.log` n'existe même pas, donc Dovecot n'a jamais été lancé.
Et surtout, `docker compose exec serveur dovecot -F` démarre parfaitement :

```
master: Info: Dovecot v2.3.19.1 starting up for pop3
```

Dovecot n'est donc pas en cause du tout. Le coupable est la ligne précédente de
l'entrypoint. exim4 se détache normalement du terminal avec `-bd`, **sauf quand
son processus père est le PID 1** : il se croit alors lancé par un système
d'init façon systemd et reste au premier plan. Dans un conteneur, l'entrypoint
*est* le PID 1. `exim4 -bd` ne rendait donc jamais la main, le script restait
bloqué sur cette ligne, et tout ce qui suit, y compris le démarrage de Dovecot,
n'était jamais exécuté.

La preuve, sans outil particulier. bash garde le script ouvert sur le
descripteur 255, et la position de lecture dit à quelle ligne il en est :

```bash
docker compose exec serveur cat /proc/1/fdinfo/255   # pos: 864
docker compose exec serveur sh -c 'head -c 864 /usr/local/bin/entrypoint.sh | tail -3'
```

L'octet 864 tombe pile après `exim4 -bd -oX "${SMTP_PORT}" -q15m`. `ps -ef`
confirme : exim4 a bien le PID 1 pour père, et `cat /proc/1/wchan` renvoie
`do_wait`, l'entrypoint attend son enfant.

Correctif dans `serveur/entrypoint.sh` : demander explicitement le premier plan
avec `-bdf` et gérer la mise en tâche de fond soi même, ce qui donne le même
comportement quel que soit le père.

```bash
exim4 -bdf -oX "${SMTP_PORT}" -q15m &
EXIM_PID=$!
```

Le `healthcheck` teste maintenant les deux ports, et l'entrypoint surveille les
deux démons avec `wait -n` : si l'un des deux meurt, le conteneur meurt avec
lui au lieu de rester `Up` avec un service manquant.

Morale utile pour le rendu : un conteneur `Up` ne prouve rien, et un service qui
démarre à la main ne prouve pas que l'orchestration le démarre.

Piège vu ici : `log_path = /dev/stderr` semble pratique en conteneur, mais
Dovecot n'arrive pas toujours à ouvrir ce chemin. Il s'arrête alors en écrivant
le message dans le fichier qu'il ne peut pas ouvrir, donc `docker compose logs`
reste vide et la panne est muette. Le journal pointe maintenant vers
`/var/log/dovecot.log`, que l'entrypoint diffuse avec `tail -F`.

`+OK 0 messages` alors que `/var/mail/alice` n'est pas vide : le `mail_location`
de Dovecot ne pointe pas au bon endroit. Il doit rester en mbox sur
`/var/mail/%u`.

Authentification POP3 refusée : tester avec `doveadm auth test alice`. Si PAM
pose problème dans le conteneur, décommenter le bloc `passdb shadow` de
`99-tp.conf` et redémarrer le serveur.

Mail bloqué en file d'attente : `exim4 -bp` pour lister, `exim4 -qff` pour forcer
un passage, `/var/log/exim4/mainlog` pour la raison exacte.
## Partie TELNET (§2) — ajout du binôme telnet

Le serveur héberge aussi un service **TELNET** (port 23), lancé par le
superdaemon `inetd`. Détails, choix de config et tableau des faiblesses dans
[`rapport-partie-telnet.md`](rapport-partie-telnet.md).

Vérifier / tester :

```bash
docker compose exec serveur netstat -antp | grep ':23'   # 0.0.0.0:23 LISTEN inetd
docker compose exec client telnet 10.99.0.10             # login tptelnet / tptelnet123
```

Fichiers concernés : `serveur/Dockerfile` (paquets inetd + telnetd + tcpd,
compte `tptelnet`, `update-inetd --enable telnet`), `serveur/entrypoint.sh`
(démarrage d'`inetd`, port telnet variable pour le §4), `serveur/healthcheck.sh`
(le port 23 doit écouter), `docker-compose.yml` (`TELNET_PORT`).
