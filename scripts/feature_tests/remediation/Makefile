export NUM_OF_MASTER_REPLICAS := 3
export NUM_OF_WORKER_REPLICAS := 1
export NUM_NODES := 4

all: provision remediation deprovision

provision:
	./../feature_test_provisioning.sh

remediation:
	./remediation.sh

deprovision:
	./../feature_test_deprovisioning.sh
