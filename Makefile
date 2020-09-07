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

setup_env_ug:
	./scripts/feature_tests/setup_env.sh "ug"

cleanup_env:
	./scripts/feature_tests/cleanup_env.sh

pivoting_test:
	make -C ./scripts/feature_tests/pivoting/

remediation_test:
	make -C ./scripts/feature_tests/remediation/

upgrade_test:
	make -C ./scripts/feature_tests/upgrade/

feature_tests: setup_env remediation_test cleanup_env pivoting_test

# feature_tests_upgrade: override CAPM3RELEASE="v0.3.2"
# feature_tests_upgrade: override CAPIRELEASE="v0.3.4"
 # TODO: uncomment above 'override' lines when
# https://github.com/metal3-io/metal3-dev-env/issues/427 is fixed
feature_tests_upgrade: setup_env upgrade_test

.PHONY: all install_requirements configure_host launch_mgmt_cluster clean delete_mgmt_cluster host_cleanup verify test lint
