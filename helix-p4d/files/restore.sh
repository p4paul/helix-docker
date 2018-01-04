#!/bin/bash

## Test Checkpoint exists
if [ ! -L $P4CKP/latest ]; then
  echo "Error: Checkpoint for link $P4CKP/latest not found."
  exit -1
fi

## Stop Perforce
p4dctl stop main
until ! p4 info -s 2> /dev/null; do sleep 1; done

## Save current data base
mkdir -p $P4ROOT/save
mv $P4ROOT/db.* $P4ROOT/save

## Restore and Upgrade Checkpoint
p4d $P4CASE -r $P4ROOT -jr -z $P4CKP/latest
p4d $P4CASE -r $P4ROOT -xu

## Start Perforce
p4dctl start main
until p4 info -s; do sleep 1; done

