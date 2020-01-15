#!/bin/bash

if [ $# -ne 1 ]; then
  echo "Usage $0 <path to env file>"
  exit 1
fi

source $1
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export WALE_S3_PREFIX
export AWS_ENDPOINT
export AWS_S3_FORCE_PATH_STYLE
export AWS_REGION
export WALG_PGP_KEY_PATH
export WALG_GPG_KEY_ID

wal-g backup-list

echo -n "Name of basebackup to restore: "
read BASEBACKUP_NAME
echo -n "Timestamp to restore or 'latest', ex: '2019-12-31 19:58:55': "
read TIMESTAMP
echo -n "Delete current data or backup it locally, you need space available (delete/backup): "
read DELETE_BACKUP

echo "Stopping current pg instance"
puppet agent --disable "Backup restoration"
systemctl stop postgresql-12.service
cd /var/lib/pgsql/12/
if [ "$DELETE_BACKUP" = "delete" ]; then
  echo "Delete current data"
  rm -fr data
else
  echo "Backup current data in /var/lib/pgsql/12/data.before-restore"
  mv data data.before-restore
fi

echo "Download basebackup $BASEBACKUP_NAME"
wal-g backup-fetch data $BASEBACKUP_NAME
cd data

echo "Configure recovery"
touch recovery.signal
echo "restore_command = '/usr/local/bin/restore_command.sh /usr/local/bin/exporter.env %f %p'" >> postgresql.auto.conf
sed -i "s/listen_addresses = '\*'/listen_addresses = 'localhost'/" postgresql.conf

if [ "$TIMESTAMP" != "latest" ]; then
  echo "recovery_target_time = '$TIMESTAMP'" >> postgresql.auto.conf
fi
chown -R postgres:postgres .

echo "Starting postgres with only local connections"
systemctl start postgresql-12.service

echo "Now you can inspect database state and log file:"
cat /var/lib/pgsql/12/data/log/*

echo
echo
echo
echo -n "Restart postgres with connections from the network ? (yes/no): "
read RESTART

if [ "$RESTART" = 'yes' ]; then
  sed -i "s/listen_addresses = 'localhost'/listen_addresses = '*'/" postgresql.conf
  systemctl restart postgresql-12.service
  puppet agent --enable
else
  echo "Open connections run:"
  echo sed -i "s/listen_addresses = 'localhost'/listen_addresses = '*'/" postgresql.conf
  echo systemctl restart postgresql-12.service
  echo puppet agent --enable
fi