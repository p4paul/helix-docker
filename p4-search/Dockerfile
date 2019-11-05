FROM ubuntu:xenial

LABEL vendor="Perforce Software"
LABEL maintainer="Paul Allen (pallen@perforce.com)"

# Update Ubuntu and add Perforce Package Source
RUN \
  apt-get update && \
  apt-get install -y wget unzip vim netcat lsb-core net-tools rsyslog && \
  apt-get install -y openjdk-8-jdk && \
  wget -qO - https://package.perforce.com/perforce.pubkey | apt-key add - && \
  echo "deb http://package.perforce.com/apt/ubuntu xenial release" > /etc/apt/sources.list.d/perforce.list && \
  apt-get update
  
RUN apt-get install -y helix-cli

ADD http://ftp.perforce.com/perforce/r16.1/bin.java/p4search.tgz /p4-search

