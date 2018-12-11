#!/bin/bash

/opt/perforce/swarm/sbin/configure-swarm.sh --non-interactive \
    --p4port ${P4PORT} \
    --swarm-user ${SWARMUSER} --swarm-passwd ${SWARMPASSWD} \
    --swarm-host ${SWARMHOST} --email-host ${MAILHOST} \
    --create --create-group --force \
    --super-user ${P4USER} --super-passwd ${P4PASSWD}

## Login
echo $P4PASSWD > pass.txt
p4 login < pass.txt

## Remove all triggers
echo "Triggers:" | p4 triggers -i

## Check in the Swarm trigger Perl script
p4 set P4CLIENT=swarm.triggers.ws
p4 client -i < /home/swarm/client.p4s
sed -i "s|%SWARMHOST%|$SWARMHOST|g" /home/swarm/swarm-trigger.conf
sed -i "s|%SWARMTOKEN%|$SWARMTOKEN|g" /home/swarm/swarm-trigger.conf
p4 add /home/swarm/swarm-trigger.pl
p4 add /home/swarm/swarm-trigger.conf
p4 submit -d "Swarm trigger"

## Install the Swarm triggers
p4 triggers -i < /home/swarm/swarm.p4s

echo "Swarm setup finished."