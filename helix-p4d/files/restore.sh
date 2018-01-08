#!/bin/bash

## Find latest checkpoint
/usr/local/bin/latest_checkpoint.sh

## Test Checkpoint exists
if [ ! -L $P4CKP/latest ]; then
  echo "Error: Checkpoint for link $P4CKP/latest not found."
  exit -1
fi

## Stop Perforce
p4 admin stop
until ! p4 info -s 2> /dev/null; do sleep 1; done

## Save current data base
mkdir -p $P4ROOT/save
mv $P4ROOT/db.* $P4ROOT/save

## Set server name
echo $P4NAME > $P4ROOT/server.id

## Restore and Upgrade Checkpoint
p4d $P4CASE -r $P4ROOT -jr -z $P4CKP/latest
p4d $P4CASE -r $P4ROOT -xu

## Set key environment variables
p4d $P4CASE -r $P4ROOT "-cset ${P4NAME}#server.depot.root=${P4DEPOTS}"
p4d $P4CASE -r $P4ROOT "-cset ${P4NAME}#journalPrefix=${P4CKP}/${JNL_PREFIX}"

## Start Perforce
p4d $P4CASE -r$P4ROOT -p$P4PORT -L$P4LOG -J$P4JOURNAL -d
until p4 info -s; do sleep 1; done
