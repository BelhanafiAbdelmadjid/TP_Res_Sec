# Partie MAIL — à mettre après la section 2 (TELNET)

## Le lien avec ta partie

- Ta section installe le **service** telnetd (port 23). Moi j'utilise la **commande** telnet comme client pour parler SMTP et POP3 à la main. Pas la même chose.
- Même base d'utilisateurs : `/etc/passwd` + `/etc/shadow`. Donc **un mot de passe capturé en POP3 ouvre ton shell Telnet**, et l'inverse.
- Trois logins en clair, trois formes différentes dans la capture (voir section 7).

## 3. Installer et configurer le MAIL

SMTP = transfert (exim4, **25/TCP**). POP3 = accès à la boîte (dovecot, **110/TCP**).
SMTP dépose la lettre, POP3 ouvre la boîte. Tout en clair, comme Telnet.

```
apt-get update
apt-cache search pop3                       # ipopd n'existe plus sur Debian 11/12
apt-get install -y exim4-daemon-light dovecot-pop3d
```

> `ipopd` (UW IMAP) est retiré de Debian. On prend `dovecot-pop3d`, même POP3,
> même port 110. À justifier dans le rendu.

**exim4** — `/etc/exim4/update-exim4.conf.conf` :

```
dc_local_interfaces='0.0.0.0'               # sinon écoute que sur 127.0.0.1
dc_relay_nets='10.99.0.0/24'                # qui a le droit de relayer
dc_localdelivery='mail_spool'               # mbox dans /var/mail
```

```
update-exim4.conf                           # génère la config
exim4 -bdf -oX 25 -q15m                     # lance le daemon
```

**dovecot** — `/etc/dovecot/conf.d/99-tp.conf` :

```
protocols = pop3
listen = *
ssl = no                                    # trafic lisible dans Wireshark
disable_plaintext_auth = no
mail_location = mbox:~/mail:INBOX=/var/mail/%u   # doit matcher exim4
```

Si `mail_location` ne pointe pas au bon endroit : le mail est livré mais POP3 dit
`+OK 0 messages`. Piège classique.

**Vérification**, même commande que pour ton 23 :

```
netstat -antp | grep -E ':25|:110'
```

**Comptes** : `useradd alice`, `useradd bob`. Pas de base propre, `/etc/passwd` et
`/etc/shadow` comme Telnet. Test : `doveadm auth test alice`.

## 4. Envoyer un mail (point 3.e)

```
telnet 10.99.0.10 25
```

```
EHLO client.tp.local              # 250-serveur Hello ...
MAIL FROM:<bob@mail.tp.local>     # 250 OK        <- enveloppe
RCPT TO:<alice@mail.tp.local>     # 250 Accepted
DATA                              # 354
Subject: test TP1
From: bob@mail.tp.local
                                  # <- ligne vide obligatoire
Corps du message.
.                                 # 250 OK id=...
QUIT                              # 221
```

Codes : 2xx accepté, 3xx attend la suite, 4xx temporaire, 5xx définitif.

**Le point à points :** l'enveloppe (`MAIL FROM`) est indépendante de l'en-tête
`From:`. Rien ne vérifie que ça correspond → **usurpation d'expéditeur en 3 lignes**.

Vérifier : `cat /var/mail/alice`, `exim4 -bp`, `tail /var/log/exim4/mainlog`.

## 5. Relire en POP3 (point 3.f)

```
telnet 10.99.0.10 110
```

```
USER alice          # +OK
PASS alice          # +OK Logged in.
STAT                # +OK 1 527
LIST                # +OK 1 messages:
RETR 1              # +OK 527 octets, puis le message
DELE 1              # +OK Marked to be deleted.
QUIT                # +OK Logging out, messages deleted.
```

Réponses `+OK` / `-ERR`, pas de codes numériques. Trois états :
**AUTHORIZATION** (`USER`/`PASS`) → **TRANSACTION** (`STAT`, `RETR`, `DELE`) →
**UPDATE** au `QUIT`.

`DELE` ne supprime pas, il **marque**. La suppression a lieu au `QUIT`. Un `RSET`
avant annule tout.

## 6. Changer les ports (point 4)

exim4 : `exim4 -bdf -oX 2525`. dovecot : `inet_listener pop3 { port = 1110 }`.
Chez toi c'était `/etc/services` + inetd → à comparer dans le rendu.

`nmap -sV -p- 10.99.0.10` retrouve quand même les trois services : les bannières
les trahissent. **Changer un port ne protège rien.**

## 7. La capture : trois logins, trois formes (point 7.e)

| Protocole | Dans la capture |
|---|---|
| Telnet 23 | **caractère par caractère**, un paquet par touche, il faut Follow TCP Stream |
| POP3 110 | `USER` / `PASS` en **ASCII brut**, lisibles direct |
| SMTP 25 (`AUTH LOGIN`) | **base64** — `echo dGVzdA== \| base64 -d` |

Piège : base64 est un **encodage**, pas un chiffrement. Écrire « chiffré » = point perdu.

Capturer depuis l'attaquant, pas depuis l'hôte (sur `br-xxxx` on voit tout sans
attaque, la démo tombe à plat) :

```bash
docker compose exec attaquant tcpdump -i eth0 -n -A 'tcp port 23 or tcp port 25 or tcp port 110'
```

Capture **avant** et **après** ARP spoofing, c'est ça qui est demandé.

## 8. Faiblesses (Telnet + Mail)

| Faiblesse | Conséquence | Contre-mesure |
|---|---|---|
| Telnet en clair | shell repris | SSH |
| POP3 `USER`/`PASS` en clair | compte repris | POP3S 995, ou STLS |
| **Base users commune** | 1 mot de passe = les 2 services | comptes séparés, 2FA |
| SMTP `DATA` en clair | lecture du courrier | STARTTLS, chiffrement bout en bout |
| `MAIL FROM` non authentifié | usurpation | SPF, DKIM, DMARC |
| `AUTH LOGIN` base64 | décodage immédiat | TLS avant `AUTH` |
| `dc_relay_nets` trop large | relais ouvert | limiter au `/24` |

**STARTTLS** : exim l'annonce (`250-STARTTLS`) mais telnet ne le demande jamais →
tout part en clair. Un MITM peut retirer la ligne pour forcer le clair
(**attaque par déclassement**). D'où les ports 465 et 995 dédiés.

## 9. Panne rencontrée

Port 25 OK, port 110 `Connection refused`, conteneur `Up`, logs **vides**.
`dovecot -F` à la main marche → Dovecot n'est pas en cause.

Cause : **exim4 `-bd` ne se détache pas quand son père est le PID 1** (il se croit
sous systemd). Dans le conteneur l'entrypoint *est* le PID 1 → exim bloque le
script, Dovecot n'est jamais lancé.

Preuve : `cat /proc/1/fdinfo/255` donne la position de lecture du script → pile
après la ligne `exim4 -bd`. `cat /proc/1/wchan` → `do_wait`.

Correctif : `exim4 -bdf -oX 25 -q15m &`

À retenir : un conteneur `Up` ne prouve pas qu'un service écoute, et un service
qui démarre à la main ne prouve pas que l'orchestration le démarre.

## Pour une seule capture avec les 3 services

```
apt-get install -y inetutils-telnetd openbsd-inetd
update-inetd --enable telnet
/etc/init.d/openbsd-inetd restart
netstat -antp | grep -E ':23|:25|:110'
```
