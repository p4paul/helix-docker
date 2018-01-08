#!/bin/bash

/opt/perforce/swarm/sbin/configure-swarm.sh --non-interactive \
    --force --p4port ${P4PORT} \
    --swarm-user ${SWARMUSER} --swarm-passwd ${SWARMPASSWD} \
    --swarm-host ${SWARMHOST} --email-host ${MAILHOST} \
    --create --create-group \
    --super-user ${P4USER} --super-passwd ${P4PASSWD}
