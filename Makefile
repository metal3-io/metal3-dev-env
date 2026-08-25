all: install_requirements configure_host launch_mgmt_cluster verify

nodep: configure_host launch_mgmt_cluster verify

ci_run: configure_host launch_mgmt_cluster verify

install_requirements:
	sudo ./01_prepare_host.sh

configure_host:
	sudo ./02_configure_host.sh

launch_mgmt_cluster:
	sudo ./03_launch_mgmt_cluster.sh

# Verifies the initial environment setup and BMH configuration.
verify:
	sudo ./04_verify.sh

clean: delete_mgmt_cluster host_cleanup

delete_mgmt_cluster:
	sudo ./cluster_cleanup.sh

host_cleanup:
	sudo ./host_cleanup.sh

test: provision pivot repivot deprovision

lint:
	./hack/shellcheck.sh

prepull_images:
	sudo ./lib/image_prepull.sh

pivot:
	sudo ./tests/scripts/pivot.sh

repivot:
	sudo ./tests/scripts/repivot.sh

provision:
	sudo ./tests/scripts/provision.sh

deprovision:
	sudo ./tests/scripts/deprovision.sh

# Verifies the provisioned target cluster and installs CNI to make the cluster
# ready.
verify_provision:
	sudo ./tests/scripts/verify.sh

.PHONY: all ci_run install_requirements configure_host launch_mgmt_cluster clean delete_mgmt_cluster host_cleanup verify test lint  prepull_images pivot repivot provision deprovision
