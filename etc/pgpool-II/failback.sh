#!/bin/bash

#Postgres data directory
postgres_datadir='/var/lib/pgsql/data'
#Postgres configuration directory
postgres_configdir=$postgres_datadir
#Postgres user ssh key
postgres_user_key='/var/lib/pgsql/.ssh/id_rsa'
#Pgpool configuration directory
pgpool_configdir='/etc/pgpool-II'
pgpool_username='pgpool'
pgpool_password=$PGPOOL_PASSWD
current_master_id=1
#Get postgres master name
current_master_name=$(pcp_node_info 10 localhost 9898 $pgpool_username $pgpool_password $current_master_id | cut -d' ' -f1)
#Get postgres slave id
[ $current_master_id == 0 ] && current_slave_id=1 || current_slave_id=0
#Get postgres slave name
current_slave_name=$(pcp_node_info 10 localhost 9898 $pgpool_username $pgpool_password $current_slave_id | cut -d' ' -f1)

echo "Current master: $current_master_name"
echo "Current slave: $current_slave_name"

#Test if pgpool is running
CheckIfPgpoolIsRunning () {
    #Send signal 0 to pgpool to check if it's running
    if ! killall -0 pgpool; then echo "[ERROR] Pgpool is not running !"; exit 1; fi;
}

AttachNodeToPgpool () {
   #pcp_attach_node is a command that permit to attach a specific postgres server (identified by 6th parameter) to pgpool.
   #pcp_attach_node dont return a good error code when it fails so here if I catch "BackendError" message in stderr I presume
   #that attachment failed.
   #TODO:find a condition to break the folowing loop if attachment fails.
   pcp_detach_node 10 localhost 9898 $pgpool_username $pgpool_password $1;
   while [ "`pcp_attach_node 10 localhost 9898 $pgpool_username $pgpool_password $1`" == "BackendError" ]
    do
        pcp_attach_node 10 localhost 9898 $pgpool_username $pgpool_password $1;
        #This sleep is recommanded to avoid stressing pgpool in this infinite loop.
        sleep 5;
    done
}

Failback () {

    new_master_name=$current_slave_name
    new_master_id=$current_slave_id
    new_slave_name=$current_master_name
    new_slave_id=$current_master_id

    echo "New master: $new_master_name($new_master_id)"
    echo "New slave: $new_slave_name($new_slave_id)"

    # Start new slave/master with online recovery
    echo "[INFO] Performing online slave recovery..."
    ssh -t -i $postgres_user_key postgres@$new_master_name "bash /var/lib/pgsql/streaming-replication.sh $new_slave_name"
    echo "[OK] Online recovery completed."


    #Setup old master config to slave mode
    echo "[INFO] Setting up configuration for the new slave node '$new_slave_name'..."
    ssh -t -t -i $postgres_user_key postgres@$new_slave_name "sudo systemctl stop postgresql"
    ssh -i $postgres_user_key postgres@$new_slave_name "cp -p $postgres_configdir/postgresql.conf.slave $postgres_configdir/postgresql.conf"
    echo "mv $postgres_datadir/recovery.done $postgres_datadir/recovery.conf"
    ssh -i $postgres_user_key postgres@$new_slave_name  "[ -f $postgres_datadir/recovery.done ] && mv $postgres_datadir/recovery.done $postgres_datadir/recovery.conf"
    ssh -i $postgres_user_key postgres@$new_slave_name "[ -f $PGPOOL_TRIGGER_FAILOVER ] && rm $PGPOOL_TRIGGER_FAILOVER"
    # Switch slave to new master
    echo "[INFO] Setting up configuration for the new master '$new_master_name'..."
    ssh -i $postgres_user_key postgres@$new_master_name "[ -f $PGPOOL_TRIGGER_FAILOVER ] && rm $PGPOOL_TRIGGER_FAILOVER"
    ssh -i $postgres_user_key postgres@$new_master_name "[ -f $postgres_datadir/recovery.conf ] && mv $postgres_datadir/recovery.conf $postgres_datadir/recovery.done"
    ssh -i $postgres_user_key postgres@$new_master_name "cp -p $postgres_configdir/postgresql.conf.master $postgres_configdir/postgresql.conf"
    echo "[INFO] Deleting trigger files from PGPool Server Pair"
    ssh -i $postgres_user_key postgres@$PGPOOL_FAILOVER_HOST "[ -f $PGPOOL_TRIGGER_FAILOVER ] && rm -f $PGPOOL_TRIGGER_FAILOVER"
    [ -f $PGPOOL_TRIGGER_FAILOVER ] && rm -f $PGPOOL_TRIGGER_FAILOVER
    echo "[INFO] Restarting new master..."
    ssh -t -t -i $postgres_user_key postgres@$new_master_name "sudo systemctl restart postgresql"
    status=$(ssh -i $postgres_user_key postgres@$new_master_name "if ! killall -0 postgres; then echo 'error'; else echo 'running'; fi;")
    if [ $status == "error" ]
    then
        echo "[ERROR] New postgres master not running !";
        exit 0;
    else
        echo "[OK] New master started.";
    fi

    echo "[INFO] Performing master restart streaming"
    ssh -t -i $postgres_user_key postgres@$new_master_name "bash /var/lib/pgsql/restart-streaming-replication.sh $new_slave_name"
    echo "[OK] Restarted streaming completed."



    echo "[INFO] Restarting new slave..."
    ssh -t -t -i $postgres_user_key postgres@$new_slave_name "sudo systemctl restart postgresql"
    status=$(ssh -i $postgres_user_key postgres@$new_slave_name "if ! killall -0 postgres; then echo 'error'; else echo 'running'; fi;")
    if [ $status == "error" ]
    then
        echo "[ERROR] New postgres slave not running !";
        exit 0;
    else
        echo "[OK] New slave started.";
    fi

    #Write changes to pgpool.conf file to keep the same current master and slave nodes even after pgpool reboot.
    #sed -i "s/^backend_hostname0.*/backend_hostname0='$new_master_name'/" $pgpool_configdir/pgpool.conf
    #sed -i "s/^backend_hostname1.*/backend_hostname1='$new_slave_name'/" $pgpool_configdir/pgpool.conf
    #echo "[OK] Pgpool configuration file updated."

    #Attach new master to pgpool
    echo "[INFO] Attaching new master node '$new_master_name'..."
    AttachNodeToPgpool "$new_master_id"
    echo "[OK] New master node '$new_master_name' has been successfully reattached to pgpool."

    #Attach new slave to pgpool
    echo "[INFO] Attaching new slave node '$new_slave_name'..."
    AttachNodeToPgpool "$new_slave_id"
    echo "[OK] New slave node '$new_slave_name' has been successfully reattached to pgpool."

    echo "Assure the slave node is streaming: ps -ef | grep receiver"

}

CheckIfPgpoolIsRunning
Failback
