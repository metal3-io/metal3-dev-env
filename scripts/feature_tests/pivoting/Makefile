M3PATH := "$(dirname "$(readlink -f "${0}")")../../../"
NUM_OF_MASTER_REPLICAS := 1
NUM_OF_WORKER_REPLICAS := 1

all: provision pivoting cleanup

provision:
	./../feature_test_provisioning.sh

pivoting:
	./../../v1alphaX/pivot.sh

cleanup:
	make clean -C "${M3PATH}"
