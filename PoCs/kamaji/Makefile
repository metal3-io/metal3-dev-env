NUM_BMH ?= 3

.PHONY: cluster
cluster: bmhs
	kubectl apply -k ClusterResourceSets
	kubectl apply -k setup-scripts
	kubectl apply -k metal3/cluster

.PHONY: pivot
pivot: cluster
	./metal3/pivot.sh

.PHONY: kamaji
kamaji:
	KUBECONFIG=kubeconfig.yaml ./kamaji.sh

.PHONY: bmhs
bmhs:
	NUM_BMH=$(NUM_BMH) ./metal3/create-bmhs.sh

.PHONY: setup
setup: prereq
	./metal3/setup.sh

.PHONY: prereq
prereq: images credentials ClusterResourceSets

.PHONY: ClusterResourceSets
ClusterResourceSets: ClusterResourceSets/calico.yaml

.PHONY: credentials
credentials:
	./metal3/generate-credentials.sh

.PHONY: images
images: metal3/images/ubuntu-2404.raw

metal3/images/ubuntu-2404.img:
	mkdir -p metal3/images
	wget -O metal3/images/ubuntu-2404.img https://cloud-images.ubuntu.com/releases/noble/release-20250610/ubuntu-24.04-server-cloudimg-amd64.img

metal3/images/ubuntu-2404.raw: metal3/images/ubuntu-2404.img
	qemu-img convert -f qcow2 -O raw metal3/images/ubuntu-2404.img metal3/images/ubuntu-2404.raw

ClusterResourceSets/calico.yaml:
	kustomize build ClusterResourceSets/calico > ClusterResourceSets/calico.yaml

.PHONY: teardown
teardown:
	./metal3/clean.sh

.PHONY: clean
clean: teardown
	rm -rf metal3/images
	rm -rf metal3/tmp
