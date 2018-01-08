#!/bin/bash

/opt/perforce/swarm/sbin/configure-swarm.sh --non-interactive \
    --force --p4port ${P4PORT} \
    --swarm-user ${SWARMUSER} --swarm-passwd ${SWARMPASSWD} \
    --swarm-host ${SWARMHOST} --email-host ${MAILHOST} \
    --create --create-group \
    --super-user ${P4USER} --super-passwd ${P4PASSWD}

## Check in the Swarm trigger Perl script
p4 set P4CLIENT=swarm.triggers.ws
p4 client -i < /home/swarm/client.p4s
sed -i "s|%SWARMHOST%|$SWARMHOST|g" /home/swarm/swarm-trigger.pl
sed -i "s|%SWARMTOKEN%|$SWARMTOKEN|g" /home/swarm/swarm-trigger.pl
p4 add /home/swarm/swarm-trigger.pl
p4 submit -d "Swarm trigger"

## Install the Swarm triggers
p4 triggers -o > /home/swarm/current.p4s
cat /home/swarm/swarm.p4s >> /home/swarm/current.p4s
p4 triggers -i < /home/swarm/current.p4s
