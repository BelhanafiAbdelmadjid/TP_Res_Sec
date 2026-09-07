#!/bin/bash
# Collecte tout ce qu'il faut pour comprendre pourquoi un service n'ecoute pas.
# A lancer depuis l'hote, a la racine du projet :
#   bash tests/diag.sh
# Puis coller la sortie complete.

echo "########## docker compose ps ##########"
docker compose ps

echo
echo "########## docker compose logs serveur ##########"
docker compose logs --no-color serveur

echo
echo "########## ss -ltnp dans le serveur ##########"
docker compose exec -T serveur ss -ltnp || true

echo
echo "########## arbre des processus ##########"
docker compose exec -T serveur ps -ef || true

echo
echo "########## processus dovecot ##########"
docker compose exec -T serveur pgrep -a dovecot || echo "aucun processus dovecot"

# Si l'entrypoint est bloque sur une commande, aucun log n'apparait et les
# services suivants ne demarrent jamais. bash garde le script ouvert sur le
# descripteur 255, la position de lecture dit a quelle ligne il en est.
echo
echo "########## ou en est l'entrypoint (PID 1) ##########"
docker compose exec -T serveur sh -c '
  echo "wchan : $(cat /proc/1/wchan 2>/dev/null)"
  POS=$(awk "/^pos:/{print \$2}" /proc/1/fdinfo/255 2>/dev/null)
  if [ -n "$POS" ]; then
    echo "position de lecture : $POS octets"
    echo "--- derniere ligne lue ---"
    head -c "$POS" /usr/local/bin/entrypoint.sh | tail -3
  else
    echo "descripteur 255 absent, le PID 1 n a pas l air d etre un script bash"
  fi' || true

echo
echo "########## doveconf -n ##########"
docker compose exec -T serveur doveconf -n || true

echo
echo "########## fichiers conf.d ##########"
docker compose exec -T serveur ls -1 /etc/dovecot/conf.d/ || true

echo
echo "########## fin ##########"