# --------------------------------------------------------------------------------
# Docker configuration for P4D
# --------------------------------------------------------------------------------

FROM ubuntu:14.04

LABEL vendor="Perforce Software"
LABEL maintainer="Paul Allen (pallen@perforce.com)"

# Update Ubuntu and add Perforce Package Source
RUN \
  apt-get update && \
  apt-get install -y curl wget unzip vim && \
  wget -qO - https://package.perforce.com/perforce.pubkey | sudo apt-key add - && \
  echo "deb http://package.perforce.com/apt/ubuntu trusty release" > /etc/apt/sources.list.d/perforce.list && \
  apt-get update

# --------------------------------------------------------------------------------
# Docker ENVIRONMENT
# --------------------------------------------------------------------------------

# Default Environment
ARG P4TCP=1666
ARG P4USER=super
ARG P4PASSWD=Password!
ARG P4HOME=/p4
ARG P4ROOT=$P4HOME/root
ARG P4DEPOTS=$P4HOME/depots
ARG P4LOGDIR=$P4HOME/log
ARG P4JOURNAL=$P4LOGDIR/journal
ARG P4LOG=$P4LOGDIR/p4d.log
ARG P4ARGS=-C1

# Define Environment 
ENV P4PORT=$P4TCP
ENV P4USER=$P4USER
ENV P4PASSWD=$P4PASSWD
ENV P4HOME=$P4HOME
ENV P4ROOT=$P4ROOT
ENV P4DEPOTS=$P4DEPOTS
ENV P4JOURNAL=$P4JOURNAL
ENV P4LOG=$P4LOG
ENV P4ARGS=$P4ARGS

# --------------------------------------------------------------------------------
# Docker BUILD
# --------------------------------------------------------------------------------

# Create perforce user and install Perforce Server
RUN \
  useradd --user-group --home-dir $P4HOME --create-home --uid 1000 perforce && \
  echo perforce:$P4PASSWD | /usr/sbin/chpasswd && \
  apt-get install -y helix-p4d

# Add external files
COPY files/main.conf /etc/perforce/p4dctl.conf.d/
RUN \
  sed -i "s|%P4PORT%|$P4TCP|g" /etc/perforce/p4dctl.conf.d/main.conf && \
  sed -i "s|%P4ROOT%|$P4ROOT|g" /etc/perforce/p4dctl.conf.d/main.conf && \
  sed -i "s|%P4JOURNAL%|$P4JOURNAL|g" /etc/perforce/p4dctl.conf.d/main.conf && \
  sed -i "s|%P4LOG%|$P4LOG|g" /etc/perforce/p4dctl.conf.d/main.conf && \
  sed -i "s|%P4ARGS%|$P4ARGS|g" /etc/perforce/p4dctl.conf.d/main.conf && \
  mkdir -p $P4ROOT && chown perforce:perforce $P4ROOT && \
  mkdir -p $P4DEPOTS && chown perforce:perforce $P4DEPOTS && \
  mkdir -p $P4LOGDIR && chown perforce:perforce $P4LOGDIR && \
  chown -R perforce:perforce $P4HOME

# Expose Perforce; TCP port and volumes
EXPOSE $P4TCP
VOLUME $P4ROOT
VOLUME $P4LOGDIR
VOLUME $P4DEPOTS

# Setup basic user and security
USER perforce
ENV P4RSH="rsh:p4d $P4ARGS -r $P4ROOT -L $P4LOG -J $P4JOURNAL -i"
RUN \
  p4 -p "$P4RSH" user -o | p4 -p "$P4RSH" user -i && \
  p4 -p "$P4RSH" protect -o | p4 -p "$P4RSH" protect -i && \
  p4 -p "$P4RSH" passwd -P $P4PASSWD && \
  p4 -p "$P4RSH" configure set server.depot.root=$P4DEPOTS

# --------------------------------------------------------------------------------
# Docker RUN
# --------------------------------------------------------------------------------

ENTRYPOINT \
  p4dctl start main && \
  until p4 info -s; do sleep 1; done && \
  bash

HEALTHCHECK \
  --interval=2m \
  --timeout=10s \
  CMD p4 info -s > /dev/null || exit 1
