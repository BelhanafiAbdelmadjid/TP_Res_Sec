#!/bin/bash
# Envoie un mail de bob a alice en SMTP, puis le relit en POP3.
# A lancer depuis le conteneur client :
#   docker compose exec client bash /tests/test-mail.sh
# ou depuis l'hote apres avoir monte le dossier.
#
# Usage : test-mail.sh [serveur] [port_smtp] [port_pop3]

set -u

SERVEUR="${1:-10.99.0.10}"
SMTP_PORT="${2:-25}"
POP3_PORT="${3:-110}"

echo "=== SMTP vers ${SERVEUR}:${SMTP_PORT} ==="
printf 'EHLO client.tp.local\r\nMAIL FROM:<bob@mail.tp.local>\r\nRCPT TO:<alice@mail.tp.local>\r\nDATA\r\nSubject: test TP1\r\nFrom: bob@mail.tp.local\r\nTo: alice@mail.tp.local\r\n\r\nMessage de test envoye par script.\r\n.\r\nQUIT\r\n' \
  | nc -q 3 "${SERVEUR}" "${SMTP_PORT}"

echo
echo "Attente de la livraison locale..."
sleep 3

echo "=== POP3 vers ${SERVEUR}:${POP3_PORT} ==="
printf 'USER alice\r\nPASS alice\r\nSTAT\r\nLIST\r\nRETR 1\r\nQUIT\r\n' \
  | nc -q 3 "${SERVEUR}" "${POP3_PORT}"

echo
echo "Si RETR 1 renvoie le corps du message, la chaine SMTP vers POP3 fonctionne."