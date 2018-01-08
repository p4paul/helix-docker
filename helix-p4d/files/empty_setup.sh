#!/bin/bash

## Take password as arg or use default
P4PASSWD=${1:-Password!}

## Stop Perforce
p4 admin stop
until ! p4 info -s 2> /dev/null; do sleep 1; done

## Save current data base
mkdir -p $P4ROOT/save
mv $P4ROOT/db.* $P4ROOT/save

## Set server name
echo $P4NAME > $P4ROOT/server.id

## Start Perforce
p4d $P4CASE -r$P4ROOT -p$P4PORT -L$P4LOG -J$P4JOURNAL -d
until p4 info -s; do sleep 1; done

## Create super user and protection
p4 configure set $P4NAME#server.depot.root=$P4DEPOTS
p4 configure set $P4NAME#journalPrefix=$P4CKP/$JNL_PREFIX
p4 user -o | p4 -p "$P4RSH" user -i
p4 protect -o | p4 -p "$P4RSH" protect -i
p4 passwd -P $P4PASSWD
