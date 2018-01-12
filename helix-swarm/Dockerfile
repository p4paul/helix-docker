# --------------------------------------------------------------------------------
# Docker configuration for P4D
# --------------------------------------------------------------------------------

FROM ubuntu:14.04

LABEL vendor="Perforce Software"
LABEL maintainer="Paul Allen (pallen@perforce.com)"

# Update Ubuntu and add Perforce Package Source
RUN \
  apt-get update && \
  apt-get install -y wget curl unzip && \
  wget -qO - https://package.perforce.com/perforce.pubkey | sudo apt-key add - && \
  echo "deb http://package.perforce.com/apt/ubuntu trusty release" > /etc/apt/sources.list.d/perforce.list && \
  apt-get update

# Create swarm user and install Helix Swarm
RUN \
  useradd --user-group --home-dir /home/swarm --create-home --uid 1000 swarm && \
  apt-get install -y helix-cli && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y helix-swarm

# --------------------------------------------------------------------------------
# Docker ENVIRONMENT
# --------------------------------------------------------------------------------

# Default Environment
ARG P4PORT=perforce:1666
ARG P4USER=super
ARG P4PASSWD=Password!
ARG SWARMHOST=localhost
ARG SWARMUSER=swarm
ARG SWARMPASSWD=$P4PASSWD
ARG SWARMTOKEN=00000000-0000-0000-0000-000000000000
ARG MAILHOST=$MAILHOST

# Configure Swarm Environment
ENV P4PORT=$P4PORT \
  P4USER=$P4USER \
  P4PASSWD=$P4PASSWD \
  SWARMHOST=$SWARMHOST \
  SWARMUSER=$SWARMUSER \
  SWARMPASSWD=$SWARMPASSWD \
  SWARMTOKEN=$SWARMTOKEN \
  MAILHOST=$MAILHOST

EXPOSE 80

# Add external files
COPY files/setup.sh /opt/perforce/swarm/setup.sh

# Configure Apache/Swarm
RUN \
  chmod +x /opt/perforce/swarm/setup.sh && \
  chown -R www-data:www-data /opt/perforce/swarm/data && \
  a2dissite 000-default && \
  mkdir -p /opt/perforce/swarm/data/queue/tokens && \
  touch /opt/perforce/swarm/data/queue/tokens/$SWARMTOKEN

USER swarm
COPY files/swarm.p4s /home/swarm/swarm.p4s
COPY files/client.p4s /home/swarm/client.p4s
COPY files/swarm-trigger.pl /home/swarm/swarm-trigger.pl

# --------------------------------------------------------------------------------
# Docker RUN
# --------------------------------------------------------------------------------

USER root
ENTRYPOINT \
  cron start && \
  /opt/perforce/swarm/setup.sh && \
  bash

HEALTHCHECK \
  --interval=2m \
  --timeout=10s \
  CMD curl --fail http://localhost/api/version || exit 1
