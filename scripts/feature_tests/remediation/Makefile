NUM_OF_MASTER_REPLICAS := 1
NUM_OF_WORKER_REPLICAS := 1

all: provision remediation deprovision

provision:
	./../feature_test_provisioning.sh

remediation:
	./../../v1alphaX/remediation.sh

deprovision:
	./../feature_test_deprovisioning.sh
