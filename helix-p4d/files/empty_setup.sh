#!/bin/bash

## Create super user and protection
p4 configure set $P4NAME#server.depot.root=$P4DEPOTS
p4 configure set $P4NAME#journalPrefix=$P4CKP/$JNL_PREFIX
p4 user -o | p4 user -i
p4 protect -o | p4 protect -i
p4 passwd -P $P4PASSWD
