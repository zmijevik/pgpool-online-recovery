#!/bin/bash

new_slave_name=$1

/usr/bin/psql -c "select pg_start_backup('initial_backup');"

/usr/bin/rsync -cva --inplace --exclude=pg_xlog/ --exclude recovery.conf --exclude recovery.done --exclude postmaster.pid /var/lib/pgsql/data/ $new_slave_name:/var/lib/pgsql/data/

/usr/bin/psql -c "select pg_stop_backup();";
