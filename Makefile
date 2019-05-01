all: install_requirements configure_host

install_requirements:
	./01_install_requirements.sh

configure_host:
	./02_configure_host.sh


clean: host_cleanup

host_cleanup:
	./host_cleanup.sh


.PHONY: all install_requirements configure_host clean host_cleanup
