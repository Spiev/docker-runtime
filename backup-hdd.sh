#!/bin/bash
# Mount hdd first and allow currend user right access
sudo mount /dev/sda1 /mnt/sda1/ -o uid=$UID

# Set encryption password
export RESTIC_PASSWORD=<Streng geheimes Kennwort :-D >

## Backup Immich
# DB Export is done by immich automaticly every night, so we can simply backup the folder containing the sql backup
restic -r /mnt/sda1/restic-repo backup ~/docker/immich/library

## Backup paperless
# backup paperless db first
docker exec -t paperless-db-1 pg_dumpall -v -c -U paperless | gzip > ~/docker/paperless/library/backup/paperless_`date +%Y-%m-%d"_"%H_%M_%S`.sql.gz
# Backup paperless
restic -r /mnt/sda1/restic-repo backup ~/docker/paperless/library

# umount hdd
sudo umount /mnt/sda1/
