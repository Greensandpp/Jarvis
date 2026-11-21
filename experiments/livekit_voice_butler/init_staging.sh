#!/bin/sh
set -eu
# Railway mounts new volumes as root. Initialize only this dedicated directory,
# then drop privileges before serving HTTP or opening a provider connection.
mkdir -p /data
chown voice:voice /data
chmod 700 /data
exec gosu voice sh /app/start_staging.sh
