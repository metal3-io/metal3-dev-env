export MAX_SURGE_VALUE := 0
export NUM_OF_MASTER_REPLICAS := 3
export NUM_OF_WORKER_REPLICAS := 0

all: provision node_reuse deprovision

provision:
	./../feature_test_provisioning.sh

node_reuse:
	./node_reuse.sh

deprovision:
	./../feature_test_deprovisioning.sh