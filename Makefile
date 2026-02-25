all: install_requirements configure_host launch_mgmt_cluster verify

nodep: configure_host launch_mgmt_cluster verify

ci_run: configure_host launch_mgmt_cluster verify

install_requirements:
	./01_prepare_host.sh

configure_host:
	./02_configure_host.sh

launch_mgmt_cluster:
	./03_launch_mgmt_cluster.sh

# Verifies the initial environment setup and BMH configuration.
verify:
	./04_verify.sh

clean: delete_mgmt_cluster host_cleanup

delete_mgmt_cluster:
	./cluster_cleanup.sh

host_cleanup:
	./host_cleanup.sh

test: provision pivot repivot deprovision

lint:
	./hack/shellcheck.sh

prepull_images:
	./lib/image_prepull.sh

pivot:
	./tests/scripts/pivot.sh

repivot:
	./tests/scripts/repivot.sh

provision:
	./tests/scripts/provision.sh

deprovision:
	./tests/scripts/deprovision.sh

# Verifies the provisioned target cluster and installs CNI to make the cluster
# ready.
verify_provision:
	./tests/scripts/verify.sh

.PHONY: all ci_run install_requirements configure_host launch_mgmt_cluster clean delete_mgmt_cluster host_cleanup verify test lint  prepull_images pivot repivot provision deprovision
