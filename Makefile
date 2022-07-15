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
	./tests/05_test.sh

lint:
	./hack/shellcheck.sh

setup_env:
	./tests/feature_tests/setup_env.sh

setup_env_ug:
	./tests/feature_tests/setup_env.sh "ug"

cleanup_env:
	./tests/feature_tests/cleanup_env.sh

pivoting_test:
	make -C ./tests/feature_tests/pivoting/

repivoting_test:
	make -C ./tests/feature_tests/pivoting/ repivoting
	make -C ./tests//feature_tests/pivoting/ deprovision

remediation_test:
	make -C ./tests/feature_tests/remediation/

node_reuse_test:
	make -C ./tests/feature_tests/node_reuse/

upgrade_test:
	make -C ./tests/feature_tests/upgrade/

inspection_test:
	./tests/feature_tests/inspection_test.sh

healthcheck_test:
	make -C ./tests/feature_tests/healthcheck/

feature_tests: setup_env healthcheck_test cleanup_env pivoting_test node_reuse_test repivoting_test

feature_tests_upgrade: setup_env_ug upgrade_test

.PHONY: all install_requirements configure_host launch_mgmt_cluster clean delete_mgmt_cluster host_cleanup verify test lint
