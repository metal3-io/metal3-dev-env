#export MAX_SURGE_VALUE := 0
#export MAX_UNAVAILABLE_VALUE := 1
export NUM_OF_MASTER_REPLICAS := 3
export NUM_OF_WORKER_REPLICAS := 1

all: node_reuse_kcp node_reuse_md

node_reuse_kcp:
	./node_reuse_kcp.sh

node_reuse_md:
	./node_reuse_md.sh