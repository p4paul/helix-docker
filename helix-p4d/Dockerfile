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
ARG P4ROOT=/p4
ARG P4JOURNAL=/p4/journal
ARG P4LOG=/p4/p4d.log
ARG P4ARGS=-C0

# Define Environment 
ENV P4PORT=$P4TCP
ENV P4USER=$P4USER
ENV P4PASSWD=$P4PASSWD
ENV P4ROOT=$P4ROOT
ENV P4JOURNAL=$P4JOURNAL
ENV P4LOG=$P4LOG
ENV P4ARGS=$P4ARGS


# --------------------------------------------------------------------------------
# Docker BUILD
# --------------------------------------------------------------------------------

# Update Ubuntu
RUN \
  apt-get update && \
  apt-get install -y curl wget unzip vim 

# Add Perforce Package Source
RUN \
  wget -qO - https://package.perforce.com/perforce.pubkey | sudo apt-key add - && \
  echo "deb http://package.perforce.com/apt/ubuntu trusty release" > /etc/apt/sources.list.d/perforce.list && \
  apt-get update

# Create perforce user with UID to 1000 before p4d installation
RUN useradd --home-dir /p4 --create-home --uid 1000 perforce
RUN echo ${OSUSER}:${PSPASSWD} | /usr/sbin/chpasswd

# Install Perforce Server
RUN apt-get install -y helix-p4d

# Expose Perforce TCP port
EXPOSE ${P4TCP}

# Add external files
ADD files/main.conf /etc/perforce/p4dctl.conf.d/
RUN \
  sed -i "s|%P4PORT%|${P4TCP}|g" /etc/perforce/p4dctl.conf.d/main.conf && \
  sed -i "s|%P4ROOT%|${P4ROOT}|g" /etc/perforce/p4dctl.conf.d/main.conf && \
  sed -i "s|%P4JOURNAL%|${P4JOURNAL}|g" /etc/perforce/p4dctl.conf.d/main.conf && \
  sed -i "s|%P4LOG%|${P4LOG}|g" /etc/perforce/p4dctl.conf.d/main.conf && \
  sed -i "s|%P4ARGS%|${P4ARGS}|g" /etc/perforce/p4dctl.conf.d/main.conf && \
  chown perforce:perforce /p4 && \
  chown -R perforce:perforce /p4

# Setup basic user and security
USER perforce
ENV P4RSH="rsh:p4d $P4ARGS -r $P4ROOT -L $P4LOG -J $P4JOURNAL -i"
RUN \
	p4 -p "$P4RSH" user -o | p4 -p "$P4RSH" user -i && \
	p4 -p "$P4RSH" protect -o | p4 -p "$P4RSH" protect -i && \
	p4 -p "$P4RSH" passwd -P ${P4PASSWD} && \
	p4 -p "$P4RSH" configure set dm.user.noautocreate=2 && \
	p4 -p "$P4RSH" configure set security=4 

# --------------------------------------------------------------------------------
# Docker RUN
# --------------------------------------------------------------------------------

ENTRYPOINT \
	p4dctl start main && \	
	until nc -zw 1 localhost 1666; do sleep 1; done && \	
	bash
