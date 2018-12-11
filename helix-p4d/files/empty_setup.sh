#!/bin/bash

# Start server in Unicode mode
p4d $P4CASE -r$P4ROOT -p$P4TCP -L$P4LOG -J$P4JOURNAL -xi
p4d $P4CASE -r$P4ROOT -p$P4TCP -L$P4LOG -J$P4JOURNAL -d

## Create super user and protection
p4 configure set $P4NAME#server.depot.root=$P4DEPOTS
p4 configure set $P4NAME#journalPrefix=$P4CKP/$JNL_PREFIX
p4 user -o | p4 user -i
p4 protect -o | p4 protect -i
