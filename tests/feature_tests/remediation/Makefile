export CONTROL_PLANE_MACHINE_COUNT := 3
export WORKER_MACHINE_COUNT := 1

all: provision remediation deprovision

provision:
	./../feature_test_provisioning.sh

remediation:
	./remediation.sh

deprovision:
	./../feature_test_deprovisioning.sh
