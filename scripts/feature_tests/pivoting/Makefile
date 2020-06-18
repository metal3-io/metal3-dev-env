M3PATH := "$(dirname "$(readlink -f "${0}")")../../../"
export NUM_OF_MASTER_REPLICAS := 1
export NUM_OF_WORKER_REPLICAS := 1

all: provision pivoting deprovision

provision:
	./../feature_test_provisioning.sh

pivoting:
	./../../v1alphaX/pivot.sh

deprovision:
	./../feature_test_deprovisioning.sh
