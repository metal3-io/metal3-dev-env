export NUM_OF_MASTER_REPLICAS := 3
export NUM_OF_WORKER_REPLICAS := 1

all: provision healthcheck deprovision 

provision:
	./../feature_test_provisioning.sh

healthcheck:
	./healthcheck.sh

deprovision:
	./../feature_test_deprovisioning.sh
