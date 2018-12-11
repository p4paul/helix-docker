#!/bin/bash

# Wait for master to start
echo "Looking for Server [${P4PORT}]..."
until p4 info -s 2> /dev/null; do sleep 1; done
echo "Perforce Server [FOUND]"


## Login
echo $P4PASSWD > pass.txt
p4 login < pass.txt

# Create service user
echo -e "User: ${SERVICEUSER}\nType: service\nFullName: ${SERVICEUSER}\nEmail: ${SERVICEUSER}@${P4PORT}" | p4 user -i -f
echo -e "Group: ${SERVICEGROUP}\nTimeout: unlimited\nUsers:\n\t${SERVICEUSER}\n" | p4 group -i

# Configure master with replica details
p4 configure set "${P4NAME}#P4TARGET=${P4PORT}"
p4 configure set "${P4NAME}#server.depot.root=${P4DEPOTS}"
p4 configure set "${P4NAME}#journalPrefix=${P4CKP}/${JNL_PREFIX}"
p4 configure set "${P4NAME}#startup.1=pull -i 1"
p4 configure set "${P4NAME}#startup.2=pull -u -i 1"
p4 configure set "${P4NAME}#startup.3=pull -u -i 1"

p4 configure set "${P4NAME}#db.replication=readonly"
p4 configure set "${P4NAME}#lbr.replication=readonly"
p4 configure set "${P4NAME}#serviceUser=${SERVICEUSER}"

# Create Server entry for replica
echo -e "ServerID: ${P4NAME}\nType: server\nServices: build-server\nAddress: ${P4PORT}\n" | p4 server -i

# Add Service user to protections
p4 protect -o > /$P4HOME/protect.p4s
grep -q -F 'super user ${SERVICEUSER}' /$P4HOME/protect.p4s
if [ $? -ne 0 ]; then
	echo "Adding service user to protection table"
	echo -e "\tsuper user ${SERVICEUSER} * //..." >> /$P4HOME/protect.p4s
	p4 protect -i < /$P4HOME/protect.p4s
fi

# Login service user
echo -e "${P4PASSWD}\n${P4PASSWD}\n" | p4 passwd ${SERVICEUSER}
p4 -u ${SERVICEUSER} login < pass.txt

# take seed checkpoint and set as latest
echo "Starting Checkpoint dump..."
rm -f $P4CKP/latest $P4CKP/seed.gz $P4CKP/seed
p4 admin dump > $P4CKP/seed
gzip $P4CKP/seed
ln -f -s $P4CKP/seed.gz $P4CKP/latest
echo "Checkpoint dump complete."

# rebuild from latest checkpoint
restore.sh
