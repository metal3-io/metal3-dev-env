M3PATH := "$(dirname "$(readlink -f "${0}")")../../../"
export CONTROL_PLANE_MACHINE_COUNT := 3
export WORKER_MACHINE_COUNT := 1

all: provision fetch_manifests pivoting

provision:
	./../feature_test_provisioning.sh

fetch_manifests:
	./../../scripts/fetch_manifests.sh

pivoting:
	./pivot.sh

fetch_target_logs:
	./../../scripts/fetch_target_logs.sh

repivoting:
	./repivot.sh

deprovision:
	./../feature_test_deprovisioning.sh

upgrading:
	./upgrade.sh
