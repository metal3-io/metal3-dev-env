all: install_requirements configure_host launch_mgmt_cluster

install_requirements:
	./01_install_requirements.sh

configure_host:
	./02_configure_host.sh

launch_mgmt_cluster:
	./03_launch_mgmt_cluster.sh

verify:
	./04_verify.sh

clean: delete_mgmt_cluster host_cleanup

delete_mgmt_cluster:
	minikube delete

host_cleanup:
	./host_cleanup.sh


.PHONY: all install_requirements configure_host launch_mgmt_cluster clean delete_mgmt_cluster host_cleanup verify
