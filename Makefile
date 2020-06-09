all: install_requirements configure_host launch_mgmt_cluster verify

install_requirements:
	./01_prepare_host.sh

configure_host:
	./02_configure_host.sh

launch_mgmt_cluster:
	./03_launch_mgmt_cluster.sh

verify:
	./04_verify.sh

clean: delete_mgmt_cluster host_cleanup

delete_mgmt_cluster:
	./cluster_cleanup.sh

host_cleanup:
	./host_cleanup.sh

test:
	./05_test.sh

lint:
	./hack/shellcheck.sh

setup_env:
	./scripts/feature_tests/setup_env.sh

cleanup_env:
	./scripts/feature_tests/cleanup_env.sh

pivoting_test:
	make -C ./scripts/feature_tests/pivoting/

remediation_test:
	make -C ./scripts/feature_tests/remediation/

upgrade_test:
	make -C ./scripts/feature_tests/upgrade/

feature_tests: setup_env remediation_test cleanup_env pivoting_test

.PHONY: all install_requirements configure_host launch_mgmt_cluster clean delete_mgmt_cluster host_cleanup verify test lint
