#!/bin/bash
failed_node=$1
new_master=$2
trigger_file=$4
old_primary=$3
PGPOOL_FAILOVER_HOST=$5
(
  date
  if [ $failed_node != $old_primary ]; then
    echo "[INFO] Slave node ($failed_node) is down. Failover not triggered !";
    exit 0;
  elif [ $failed_node != 0 ]; then 
    echo "[INFO] non-primary node ($failed_node) is down. Failover not triggered !";
    exit 0
  fi
  echo "Failed node: $failed_node , New Master: $new_master"
  set -x
  /usr/bin/ssh -i /var/lib/pgsql/.ssh/id_rsa postgres@$new_master "touch $trigger_file"
  /usr/bin/ssh -i /var/lib/pgsql/.ssh/id_rsa postgres@$PGPOOL_FAILOVER_HOST "touch $trigger_file && chown postgres:postgres $trigger_file"
  /bin/touch $trigger_file && chown postgres:postgres $trigger_file
  exit 0;
) 2>&1 | tee -a /etc/pgpool-II/logs/pgpool_failover.log

/usr/local/bin/mandrill $SYSADMIN_EMAIL "PostgreSQL Failover Alert:`hostname`" "`hostname`: Failed node: $failed_node , New Master: $new_master, Make sure failover happened properly."
