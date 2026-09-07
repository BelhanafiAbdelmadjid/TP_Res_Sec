#!/bin/bash
# Un conteneur "Up" ne prouve rien. Ce test verifie que les deux ports
# ecoutent reellement, pour que docker compose ps affiche unhealthy
# au lieu d'un Up trompeur.

SMTP_PORT="${SMTP_PORT:-25}"
POP3_PORT="${POP3_PORT:-110}"
TELNET_PORT="${TELNET_PORT:-23}"

ss -ltn "sport = :${SMTP_PORT}"   | grep -q LISTEN || exit 1
ss -ltn "sport = :${POP3_PORT}"   | grep -q LISTEN || exit 1
ss -ltn "sport = :${TELNET_PORT}" | grep -q LISTEN || exit 1

exit 0