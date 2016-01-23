ID=$(curl -s http://169.254.169.254/metadata/v1/id)
HAS_FLOATING_IP=$(curl -s http://169.254.169.254/metadata/v1/floating_ip/ipv4/active)

if [ $HAS_FLOATING_IP = "false" ]; then
    n=0
    while [ $n -lt 10 ]
    do
        python /usr/local/bin/assign-ip $DO_FAILOVER_IP_PGPOOL $ID && break
        n=$((n+1))
        sleep 3
    done
fi

/etc/pgpool-II/nodes_assurehealthy

/usr/local/bin/mandrill $SYSADMIN_EMAIL "PgPool Failover Alert:`hostname`" "`hostname` is now the new pgpool server."
