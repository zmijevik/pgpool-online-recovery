node_id=$1
pcp_node_info 10 localhost 9898 pgpool $PGPOOL_PASSWD $node_id
pcp_detach_node 10 localhost 9898 pgpool $PGPOOL_PASSWD $node_id
pcp_attach_node 10 localhost 9898 pgpool $PGPOOL_PASSWD $node_id
pcp_node_info 10 localhost 9898 pgpool $PGPOOL_PASSWD $node_id
