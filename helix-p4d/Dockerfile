# --------------------------------------------------------------------------------
# Docker configuration for P4D
# --------------------------------------------------------------------------------

FROM ubuntu:14.04

LABEL vendor="Perforce Software"
LABEL maintainer="Paul Allen (pallen@perforce.com)"

# Update Ubuntu and add Perforce Package Source
RUN \
  apt-get update && \
  apt-get install -y wget unzip && \
  wget -qO - https://package.perforce.com/perforce.pubkey | sudo apt-key add - && \
  echo "deb http://package.perforce.com/apt/ubuntu trusty release" > /etc/apt/sources.list.d/perforce.list && \
  apt-get update

# --------------------------------------------------------------------------------
# Docker ENVIRONMENT
# --------------------------------------------------------------------------------

# Default Environment
ARG P4NAME=master
ARG P4TCP=1666
ARG P4USER=super
ARG P4PASSWD=Password!
ARG P4CASE=-C1

# Dynamic Environment
ENV P4NAME=$P4NAME \
  P4PORT=$P4TCP \
  P4USER=$P4USER \
  P4PASSWD=$P4PASSWD \
  P4CASE=$P4CASE \
  JNL_PREFIX=$P4NAME

# Base Environment
ENV P4HOME=/p4
ENV P4LOGDIR=$P4HOME/log

# Derrived Environment
ENV P4ROOT=$P4HOME/root \
  P4DEPOTS=$P4HOME/depots \
  P4CKP=$P4HOME/checkpoints \
  P4JOURNAL=$P4LOGDIR/journal \
  P4LOG=$P4LOGDIR/p4d.log

# --------------------------------------------------------------------------------
# Docker BUILD
# --------------------------------------------------------------------------------

# Create perforce user and install Perforce Server
RUN \
  useradd --user-group --home-dir $P4HOME --create-home --uid 1000 perforce && \
  apt-get install -y helix-p4d && \
  apt-get install -y helix-swarm-triggers

# Add external files
COPY files/clean.sh /usr/local/bin/clean.sh
COPY files/restore.sh /usr/local/bin/restore.sh
COPY files/empty_setup.sh /usr/local/bin/empty_setup.sh
COPY files/latest_checkpoint.sh /usr/local/bin/latest_checkpoint.sh
COPY files/swarm-trigger.conf /opt/perforce/etc/swarm-trigger.conf
COPY files/triggers.p4s /opt/perforce/etc/triggers.p4s

RUN \
  chmod +x /usr/local/bin/clean.sh && \
  chmod +x /usr/local/bin/restore.sh && \
  chmod +x /usr/local/bin/empty_setup.sh && \
  chmod +x /usr/local/bin/latest_checkpoint.sh && \
  mkdir -p $P4ROOT && chown perforce:perforce $P4ROOT && \
  mkdir -p $P4DEPOTS && chown perforce:perforce $P4DEPOTS && \
  mkdir -p $P4CKP && chown perforce:perforce $P4CKP && \
  mkdir -p $P4LOGDIR && chown perforce:perforce $P4LOGDIR && \
  chown -R perforce:perforce $P4HOME

# Expose Perforce; TCP port and volumes
EXPOSE $P4TCP
VOLUME $P4ROOT
VOLUME $P4LOGDIR
VOLUME $P4DEPOTS
VOLUME $P4CKP

# Setup basic user and security for an empty server
USER perforce

# --------------------------------------------------------------------------------
# Docker RUN
# --------------------------------------------------------------------------------

ENTRYPOINT \
  p4d $P4CASE -r$P4ROOT -p$P4PORT -L$P4LOG -J$P4JOURNAL -d && \
  until p4 info -s; do sleep 1; done && \
  empty_setup.sh && \
  bash

HEALTHCHECK \
  --interval=2m \
  --timeout=10s \
  CMD p4 info -s > /dev/null || exit 1
