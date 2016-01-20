#!/bin/bash
failed_node=$1
new_master=$2
trigger_file=$4
old_primary=$3
(
  date
  if [ $failed_node != $old_primary ]; then
    echo "[INFO] Slave node ($failed_node) is down. Failover not triggered !";
    exit 0;
  fi
  echo "Failed node: $failed_node , New Master: $new_master"
  set -x
  /usr/bin/ssh -i /var/lib/pgsql/.ssh/id_rsa postgres@$new_master "touch $trigger_file"
  exit 0;
) 2>&1 | tee -a /etc/pgpool-II/logs/pgpool_failover.log
