FROM debian:12

ENV DEBIAN_FRONTEND=noninteractive

# Image posee pour le binome qui traite les parties 5, 6 et 7 du sujet.
# Si un paquet manque dans votre miroir, adaptez le nom et notez le
# dans le compte rendu.
RUN apt-get update && apt-get install -y --no-install-recommends \
      nmap \
      tcpdump \
      tshark \
      ettercap-text-only \
      telnet \
      netcat-openbsd \
      iproute2 \
      iputils-ping \
      iputils-arping \
      net-tools \
      procps \
    && rm -rf /var/lib/apt/lists/*

CMD ["sleep", "infinity"]