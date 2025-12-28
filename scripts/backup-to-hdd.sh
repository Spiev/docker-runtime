#!/bin/bash

# For debugging, print script start time
echo "Script started at $(date --iso-8601=ns)"

# Variabeln setzen
# Secrets laden mit Validierung
SECRETS_FILE="/home/stefan/docker/scripts/.restic.env"

set -euo pipefail


if [[ ! -f "$SECRETS_FILE" ]]; then
    echo "ERROR: Secrets file not found: $SECRETS_FILE" >&2
    exit 1
fi

# Rechte prüfen (sollte 600 sein)
PERMS=$(stat -c %a "$SECRETS_FILE")
if [[ "$PERMS" != "600" ]]; then
    echo "WARNING: Insecure permissions on $SECRETS_FILE (found: $PERMS, expected: 600)" >&2
fi

source "$SECRETS_FILE"

# Validierung: Sind alle nötigen Variablen gesetzt?
required_vars=("RESTIC_PASSWORD" )
for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "ERROR: Required variable $var is not set" >&2
        exit 1
    fi
done



# Mount hdd first and allow currend user right access
echo "Mount /dev/sda1 to /mnt/sda1/"
sudo mount /dev/sda1 /mnt/sda1/ -o rw,uid=$UID,user,dmask=007,fmask=117

## Backup Immich
# DB Export is done by immich automaticly every night, so we can simply backup the folder containing the sql backup
echo "Copy /home/stefan/docker/immich/library to /mnt/sda1/restic-repo"
restic -r /mnt/sda1/restic-repo backup /home/stefan/docker/immich/library

## Backup paperless
# backup paperless db first
echo "Backup der Paperless DB nach /home/stefan/docker/paperless/library/backup/"
docker exec -t paperless-db-1 pg_dumpall -v -c -U paperless | gzip > /home/stefan/docker/paperless/library/backup/paperless_`date +%Y-%m-%d"_"%H_%M_%S`.sql.gz
# Backup paperless
echo "Backup der Paperless Datenbank und Files /home/stefan/docker/paperless/library nach /mnt/sda1/restic-repo"
restic -r /mnt/sda1/restic-repo backup /home/stefan/docker/paperless/library

# umount hdd
echo "Unmount /mnt/sda1/"
sudo umount /mnt/sda1/

# Credentials aus Memory löschen (best effort)
echo "Remove secrets from RAM"
unset RESTIC_PASSWORD 
