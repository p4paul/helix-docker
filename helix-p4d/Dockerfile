# --------------------------------------------------------------------------------
# Docker configuration for P4D
# --------------------------------------------------------------------------------

FROM ubuntu:14.04

MAINTAINER Paul Allen (pallen@perforce.com)

# Default Environment
ARG OSUSER=perforce
ARG PSPASSWD=Password!
ARG P4TCP=1666
ARG P4HOST=p4.helix
ARG P4USER=admin
ARG P4PASSWD=Password
ARG P4ROOT=/p4/root
ARG P4DEPOTS=/p4/depots
ARG P4LOGDIR=/p4/log
ARG P4JOURNAL=$P4LOGDIR/journal
ARG P4LOG=$P4LOGDIR/p4d.log
ARG P4ARGS=-C0

# Define Environment 
ENV P4PORT=$P4TCP
ENV P4USER=$P4USER
ENV P4PASSWD=$P4PASSWD
ENV P4ROOT=$P4ROOT
ENV P4DEPOTS=$P4DEPOTS
ENV P4JOURNAL=$P4JOURNAL
ENV P4LOG=$P4LOG
ENV P4ARGS=$P4ARGS


# --------------------------------------------------------------------------------
# Docker BUILD
# --------------------------------------------------------------------------------

# Update Ubuntu and add Perforce Package Source
RUN \
  apt-get update && \
  apt-get install -y curl wget unzip vim && \
  wget -qO - https://package.perforce.com/perforce.pubkey | sudo apt-key add - && \
  echo "deb http://package.perforce.com/apt/ubuntu trusty release" > /etc/apt/sources.list.d/perforce.list && \
  apt-get update

# Create perforce user and install Perforce Server
RUN \
  useradd --home-dir /p4 --create-home --uid 1000 perforce && \
  echo ${OSUSER}:${PSPASSWD} | /usr/sbin/chpasswd && \
  apt-get install -y helix-p4d

# Add external files
ADD files/main.conf /etc/perforce/p4dctl.conf.d/
RUN \
  sed -i "s|%P4PORT%|$P4TCP|g" /etc/perforce/p4dctl.conf.d/main.conf && \
  sed -i "s|%P4ROOT%|$P4ROOT|g" /etc/perforce/p4dctl.conf.d/main.conf && \
  sed -i "s|%P4JOURNAL%|$P4JOURNAL|g" /etc/perforce/p4dctl.conf.d/main.conf && \
  sed -i "s|%P4LOG%|$P4LOG|g" /etc/perforce/p4dctl.conf.d/main.conf && \
  sed -i "s|%P4ARGS%|$P4ARGS|g" /etc/perforce/p4dctl.conf.d/main.conf && \
  mkdir -p $P4ROOT && chown -R perforce:perforce $P4ROOT && \
  mkdir -p $P4LOGDIR && chown -R perforce:perforce $P4LOGDIR

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
	p4 -p "$P4RSH" configure set server.depot.root=$P4DEPOTS && \
	p4 -p "$P4RSH" configure set dm.user.noautocreate=2 && \
	p4 -p "$P4RSH" configure set security=4 

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